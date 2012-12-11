SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;
CREATE SCHEMA dalibo;
ALTER SCHEMA dalibo OWNER TO yang;
CREATE OR REPLACE PROCEDURAL LANGUAGE plpgsql;
ALTER PROCEDURAL LANGUAGE plpgsql OWNER TO postgres;
SET search_path = public, pg_catalog;
CREATE TYPE counters_detail AS (
	timet timestamp with time zone,
	value numeric
);
ALTER TYPE public.counters_detail OWNER TO postgres;
SET search_path = dalibo, pg_catalog;
CREATE FUNCTION pg_taille_jolie(p_valeur bigint, OUT v_jolie text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
BEGIN
  
  
  v_jolie= regexp_replace(pg_size_pretty(abs(p_valeur)),'B$','o');
  v_jolie= regexp_replace(v_jolie,'bytes$','octets');
  IF (p_valeur < 0) THEN
    v_jolie= '-'||v_jolie;
  END IF;
END;
$_$;
ALTER FUNCTION dalibo.pg_taille_jolie(p_valeur bigint, OUT v_jolie text) OWNER TO yang;
CREATE FUNCTION variation_taille_service(p_hostname text, p_service text, p_label text, p_tstamp_debut timestamp with time zone, p_duree interval, OUT v_compteur_debut numeric, OUT v_compteur_fin numeric, OUT v_compteur_delta numeric, OUT v_type_corr text, OUT v_corr double precision, OUT v_taille_un_mois numeric) RETURNS record
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$ 
  DECLARE
    v_id_service bigint;
    v_pente_lineaire double precision;
    v_pente_expo double precision;
    v_corr_lineaire double precision;
    v_corr_expo double precision;
    
  BEGIN 
  RAISE DEBUG 'parametres : % % % % %',p_hostname,p_service,p_label,p_tstamp_debut,p_duree;
    
    SELECT id INTO v_id_service FROM services WHERE hostname=p_hostname 
                                              AND   service=p_service 
                                              AND   label=p_label
    AND last_modified>now()-'1 month'::interval;
    IF NOT FOUND THEN 
      RAISE EXCEPTION 'Pas de service correspondant aux parametres'; 
    END IF; 
    
    
    
    EXECUTE 'SELECT value FROM (SELECT (unnest(records)).* FROM counters_detail_'||v_id_service||') as tmp WHERE timet < $1 ORDER BY timet DESC LIMIT 1' INTO v_compteur_debut USING p_tstamp_debut;
    EXECUTE 'SELECT value FROM (SELECT (unnest(records)).* FROM counters_detail_'||v_id_service||') as tmp WHERE timet < $1 ORDER BY timet DESC LIMIT 1' INTO v_compteur_fin USING p_tstamp_debut+p_duree;
    v_compteur_delta:=v_compteur_fin-v_compteur_debut;
    
    
    EXECUTE E'WITH
        temp_data_echantillonnage AS
      (SELECT timet, value, rank() over (partition by date_trunc(\'day\',timet) order by value desc,timet) AS rang
       FROM (SELECT (unnest(records)).* FROM counters_detail_'||v_id_service||E') as tmp
       WHERE timet>now()-\'2 month\'::interval),
        temp_data AS                                              
      (SELECT extract(epoch from timet) as time, value, ln(value) valueln 
       FROM temp_data_echantillonnage
       WHERE rang=1)
    SELECT regr_slope(value,time) AS pente_lineaire, corr(value,time) AS correlation_lineaire,
           regr_slope(valueln,time) AS pente_expo, corr(valueln,time) AS correlation_expo
    FROM temp_data' INTO v_pente_lineaire,v_corr_lineaire,v_pente_expo,v_corr_expo ;
    
    IF (v_corr_lineaire IS NULL) THEN 
      v_corr_lineaire:=1;
      v_corr_expo:=0;
    END IF;
    IF (abs(v_corr_lineaire)>=abs(v_corr_expo)-0.1) THEN
      v_corr:=round(v_corr_lineaire::numeric,2);
      v_type_corr:='Linéaire';
      v_taille_un_mois:=v_compteur_fin + v_pente_lineaire::numeric*86400*31; 
    ELSE
      v_corr:=round(v_corr_expo::numeric,2);
      v_type_corr:='Exponentielle';
      v_taille_un_mois:=exp((ln(v_compteur_fin)+v_pente_expo*86400*31)); 
    END IF;
  
  IF (v_taille_un_mois < 0) THEN
    v_taille_un_mois = 0;
  END IF;
  
  END
  $_$;
ALTER FUNCTION dalibo.variation_taille_service(p_hostname text, p_service text, p_label text, p_tstamp_debut timestamp with time zone, p_duree interval, OUT v_compteur_debut numeric, OUT v_compteur_fin numeric, OUT v_compteur_delta numeric, OUT v_type_corr text, OUT v_corr double precision, OUT v_taille_un_mois numeric) OWNER TO yang;
SET search_path = public, pg_catalog;
CREATE FUNCTION cleanup_partition(p_partid bigint, p_max_timestamp timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE
  v_cursor refcursor;
  v_record record;
  v_current_value numeric;
  v_start_range timestamptz;
  v_partname text;
  v_previous_timet timestamptz;
  v_counter integer;
  v_previous_cleanup timestamptz;
  v_cursor_found boolean;
BEGIN
  
  SELECT last_cleanup INTO v_previous_cleanup FROM services WHERE id=p_partid;
  
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  v_partname = 'counters_detail_' || p_partid;
  
  EXECUTE 'LOCK TABLE ' || v_partname;
  EXECUTE 'CREATE TEMP TABLE tmp AS SELECT (unnest(records)).* FROM '|| v_partname; 
  
  
  
  OPEN v_cursor FOR EXECUTE 'SELECT timet,value FROM tmp WHERE timet >= ' || quote_literal(v_previous_cleanup) || ' AND timet <= ' || quote_literal(p_max_timestamp) || ' ORDER BY timet';
  LOOP
    FETCH v_cursor INTO v_record;
    v_cursor_found=FOUND;
    v_counter:=v_counter+1;
    IF v_cursor_found AND v_current_value IS NULL THEN
      
      v_current_value:=v_record.value;
      v_start_range:=v_record.timet;
      v_counter:=1;
    ELSIF NOT v_cursor_found OR v_current_value <> v_record.value THEN
      
      
      
      
      IF v_counter>= 4 THEN
        RAISE DEBUG 'DELETE BETWEEN % and % on partition %, counter=%',v_start_range,v_previous_timet,p_partid,v_counter;
        EXECUTE 'DELETE FROM tmp WHERE timet > $1 AND timet < $2' USING v_start_range,v_previous_timet;
      END IF;
      EXIT WHEN NOT v_cursor_found; 
      
      v_start_range:=v_record.timet;
      v_current_value:=v_record.value;
      v_counter:=1;
    END IF;
    
    v_previous_timet:=v_record.timet;
  END LOOP;
  CLOSE v_cursor;
  
  RAISE DEBUG 'truncate %',v_partname;
  EXECUTE 'TRUNCATE ' || v_partname;
  EXECUTE 'INSERT INTO ' || v_partname || ' select date_trunc(''day'',timet),array_agg(row(timet,value)::counters_detail) from tmp group by date_trunc(''day'',timet)';
  EXECUTE 'DROP TABLE tmp';
  
  UPDATE services SET last_cleanup=p_max_timestamp WHERE id=p_partid;
  RETURN true;
END;
$_$;
ALTER FUNCTION public.cleanup_partition(p_partid bigint, p_max_timestamp timestamp with time zone) OWNER TO postgres;
CREATE FUNCTION create_partion_on_insert_service() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE 'CREATE TABLE counters_detail_'||NEW.id|| ' (date_records date,records counters_detail[])';
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
    LANGUAGE sql
    AS $$
  SELECT min(newest_record) FROM services
$$;
ALTER FUNCTION public.get_first_timestamp_db() OWNER TO postgres;
CREATE FUNCTION get_first_timestamp_db_old() RETURNS timestamp with time zone
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
ALTER FUNCTION public.get_first_timestamp_db_old() OWNER TO postgres;
CREATE FUNCTION get_last_timestamp_by_id(l_id bigint) RETURNS timestamp with time zone
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  l_timestamp timestamptz;
  l_result timestamptz='-infinity'::timestamptz;
BEGIN
  EXECUTE 'SELECT max(timet) FROM counters_detail_'||l_id INTO l_timestamp;
  IF l_timestamp IS NOT NULL THEN
    IF l_timestamp > l_result THEN
      l_result := l_timestamp;
    END IF;
  END IF;
  RETURN l_result;
END;
$$;
ALTER FUNCTION public.get_last_timestamp_by_id(l_id bigint) OWNER TO postgres;
CREATE FUNCTION get_last_timestamp_db() RETURNS timestamp with time zone
    LANGUAGE sql
    AS $$
  SELECT max(newest_record) FROM services
$$;
ALTER FUNCTION public.get_last_timestamp_db() OWNER TO postgres;
CREATE FUNCTION get_last_timestamp_db_old() RETURNS timestamp with time zone
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
ALTER FUNCTION public.get_last_timestamp_db_old() OWNER TO postgres;
CREATE FUNCTION get_last_value(i_hostname text, i_service text, i_label text) RETURNS counters_detail
    LANGUAGE plpgsql STABLE COST 10000
    AS $_$
 DECLARE
   l_id integer;
   l_query text;
   l_rvalue counters_detail;
   v_maxdate date;
 BEGIN
   RAISE debug 'Exec de get_last_value pour %,%,%',i_hostname,i_service,i_label;
   SELECT INTO l_id id FROM services WHERE hostname=i_hostname AND service=i_service AND label=i_label;
   IF FOUND THEN
     
     EXECUTE 'select max(date_records) FROM counters_detail_' || l_id INTO v_maxdate;
     l_query := 'SELECT timet, value FROM (SELECT (unnest(records)).* FROM counters_detail_' || l_id || ' WHERE date_records=$1) as tmp ORDER BY timet DESC LIMIT 1';
   ELSE
     l_query := 'SELECT NULL::timestamptz, NULL::numeric';
   END IF;
   EXECUTE l_query INTO l_rvalue USING v_maxdate;
   RETURN l_rvalue;
 END;
 $_$;
ALTER FUNCTION public.get_last_value(i_hostname text, i_service text, i_label text) OWNER TO postgres;
CREATE FUNCTION get_sampled_service_data(id_service bigint, timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer) RETURNS TABLE(timet timestamp with time zone, value numeric)
    LANGUAGE plpgsql
    AS $_$
 BEGIN
   IF (sample_sec > 0) THEN
     RETURN QUERY EXECUTE 'SELECT min(timet), max(value) FROM (SELECT (unnest(records)).* FROM counters_detail_'||id_service||' where date_records >= $1 - ''1 day''::interval and date_records <= $2) as tmp WHERE timet >= $1 AND timet <= $2  group by (extract(epoch from timet)::float8/$3)::bigint*$3' USING timet_begin,timet_end,sample_sec;
   ELSE
     RETURN QUERY EXECUTE 'SELECT min(timet), max(value) FROM (SELECT (unnest(records)).* FROM counters_detail_'||id_service||' where date_records >= $1 - ''1 day''::interval and date_records <= $2) as tmp WHERE timet >= $1 AND timet <= $2' USING timet_begin,timet_end;
   END IF;
   RETURN QUERY EXECUTE 'SELECT $1, value FROM (SELECT (unnest(records)).* FROM counters_detail_'||id_service||' where date_records >= $1 - ''1 day''::interval and date_records <= $2) as tmp WHERE timet <= $1 ORDER BY timet DESC LIMIT 1' USING timet_begin,timet_end; 
   RETURN QUERY EXECUTE 'SELECT $1, value FROM (SELECT (unnest(records)).* FROM counters_detail_'||id_service||' where date_records >= $1 - ''1 day''::interval and date_records <= $2) as tmp WHERE timet >= $2 ORDER BY timet DESC LIMIT 1' USING timet_begin,timet_end;
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
CREATE FUNCTION get_sum_sampled_service_data(id_service bigint[], timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer) RETURNS TABLE(timet timestamp with time zone, value numeric)
    LANGUAGE plpgsql
    AS $_$
DECLARE
  i int;
  curs_detail refcursor;
  record_tmp record;
  record_detail record;
  curs_detail_lower timestamptz;
  curs_detail_upper timestamptz;
BEGIN
  
  
  
  
  
  
  CREATE temp table tmp_data (timettmp timestamptz, valuetmp numeric);
  INSERT INTO tmp_data (timettmp) SELECT generate_series (timet_begin,timet_end,'1 second'::interval*sample_sec);
  CREATE INDEX tmp_indx_tmp_data ON tmp_data(timettmp);
  
  
  FOR i in array_lower(id_service,1) .. array_upper(id_service,1) LOOP
    EXECUTE 'SELECT timet FROM (SELECT (unnest(records)).* FROM counters_detail_'||id_service[i]|| ') as tmp WHERE timet<$1 ORDER BY timet ASC' INTO curs_detail_lower USING timet_begin;
    EXECUTE 'SELECT timet FROM (SELECT (unnest(records)).* FROM counters_detail_'||id_service[i]|| ') as tmp WHERE timet>$1 ORDER BY timet DESC' INTO curs_detail_upper USING timet_end;
    IF timet_begin IS NULL THEN
      timet_begin:='-infinity'::timestamptz;
    END IF;
    IF timet_end IS NULL THEN
      timet_end:='infinity'::timestamptz;
    END IF;
    OPEN curs_detail SCROLL FOR EXECUTE 'SELECT timet,value FROM (SELECT (unnest(records)).* FROM counters_detail_'||id_service[i]||') as tmp WHERE timet > $1 AND timet < $2 ORDER BY timet' USING timet_begin,timet_end;
    FOR record_tmp IN SELECT timettmp,valuetmp FROM tmp_data ORDER BY timettmp
    LOOP
      
      LOOP
        FETCH NEXT FROM curs_detail INTO record_detail;
        IF record_detail IS NULL OR record_detail.timet>record_tmp.timettmp THEN 
          EXIT;
        END IF;
      END LOOP;
      
      FETCH PRIOR FROM curs_detail INTO record_detail;
      UPDATE tmp_data SET valuetmp = (coalesce(valuetmp,0))+coalesce(record_detail.value,0) WHERE timettmp=record_tmp.timettmp;
    END LOOP;
    CLOSE curs_detail;
  END LOOP;
  RETURN QUERY SELECT timettmp, valuetmp FROM tmp_data ORDER BY timettmp;
  DROP TABLE tmp_data;
  
  
END;
  $_$;
ALTER FUNCTION public.get_sum_sampled_service_data(id_service bigint[], timet_begin timestamp with time zone, timet_end timestamp with time zone, sample_sec integer) OWNER TO yang;
CREATE FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, pmin numeric, pmax numeric, pwarning numeric, pcritical numeric, punit text) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE
  vservice record;
  vid bigint;
  vtimet timestamptz; 
BEGIN
  vtimet:='epoch'::timestamptz + ptimet * '1 second'::interval;
  
  SELECT id,state,unit,last_modified,last_cleanup,min,max,warning,critical,newest_record
  INTO vservice
  FROM services
  WHERE hostname=phostname AND service=pservice AND label=plabel;
  IF NOT FOUND THEN
    
    
    INSERT INTO services
    (hostname,service,state,label,unit,min,max,warning,critical,newest_record)
    VALUES (phostname,pservice,pservicestate,plabel,punit,pmin,pmax,pwarning,pcritical,vtimet);
    
    SELECT id,state,unit,last_modified,last_cleanup,min,max,warning,critical,newest_record
    INTO vservice
    FROM services
    WHERE hostname=phostname AND service=pservice AND label=plabel;
  END IF;
  vid:=vservice.id;
  
  
  
  IF (  vservice.last_modified + '1 day'::interval < CURRENT_DATE 
     OR vservice.state <> pservicestate 
     OR (vservice.min <> pmin OR (vservice.min IS NULL AND pmin IS NOT NULL)) 
     OR (vservice.max <> pmax OR (vservice.max IS NULL AND pmax IS NOT NULL))
     OR (vservice.warning <> pwarning OR (vservice.warning IS NULL AND pwarning IS NOT NULL))
     OR (vservice.critical <> pcritical OR (vservice.critical IS NULL AND pcritical IS NOT NULL))
     OR (vservice.unit <> punit OR (vservice.unit IS NULL AND punit IS NOT NULL))
     OR (vservice.newest_record +'5 minutes'::interval < now() )
     )
     THEN
    
    UPDATE services SET last_modified = CURRENT_DATE,
                        state = pservicestate,
                        min = pmin,
                        max = pmax,
                        warning = pwarning,
                        critical = pcritical,
                        unit = punit,
			newest_record=vtimet
    WHERE id=vid;
  END IF;
  
  
  
  
  IF vservice.last_cleanup < now() - '10 days'::interval THEN
    PERFORM cleanup_partition(vid,now()- '7 days'::interval);
  END IF;
  
  
  
  EXECUTE 'INSERT INTO counters_detail_'|| vid
          || ' VALUES (date_trunc(''day'',$1),array[row($1,$2)]::counters_detail[])'
          USING vtimet,pvalue;
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
EXECUTE 'SELECT max(timet) FROM (SELECT (unnest(records)).* FROM counters_detail_'||p_id || ') as tmp' INTO v_max;
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
EXECUTE 'SELECT min(timet) FROM (SELECT (unnest(records)).* FROM counters_detail_'||p_id||') as tmp' INTO v_min;
RETURN v_min;
END
$$;
ALTER FUNCTION public.min_timet_id(p_id bigint) OWNER TO postgres;
CREATE FUNCTION sets_newest_oldest_values() RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
vid bigint;
vmin timestamptz;
vmax timestamptz;
BEGIN
  FOR vid IN SELECT id FROM services ORDER BY id LOOP
    RAISE DEBUG 'ID: %',vid;
    EXECUTE 'SELECT min(timet) as min, max(timet) as max FROM counters_detail_'||vid
      INTO vmin,vmax;
    UPDATE services SET oldest_record=vmin, newest_record=vmax WHERE id=vid;
  END LOOP;
  RETURN true;
END
$$;
ALTER FUNCTION public.sets_newest_oldest_values() OWNER TO postgres;
CREATE FUNCTION to_epoch_tz(timestamp with time zone) RETURNS double precision
    LANGUAGE sql STABLE
    AS $_$
SELECT extract(epoch FROM $1) + extract(timezone FROM CURRENT_TIMESTAMP);
$_$;
ALTER FUNCTION public.to_epoch_tz(timestamp with time zone) OWNER TO yang;
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
    critical numeric,
    oldest_record timestamp with time zone DEFAULT now(),
    newest_record timestamp with time zone
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
CREATE TABLE test_marc (
    timet timestamp with time zone,
    value numeric
);
ALTER TABLE public.test_marc OWNER TO postgres;
CREATE TABLE test_mco (
    records counters_detail[]
);
ALTER TABLE public.test_mco OWNER TO postgres;
ALTER TABLE ONLY services ALTER COLUMN id SET DEFAULT nextval('services_id_seq'::regclass);
ALTER TABLE ONLY services
    ADD CONSTRAINT services_pkey PRIMARY KEY (id);
CREATE UNIQUE INDEX idx_services_hostname_service_label ON services USING btree (hostname, service, label);
CREATE TRIGGER create_partion_on_insert_service BEFORE INSERT ON services FOR EACH ROW EXECUTE PROCEDURE create_partion_on_insert_service();
CREATE TRIGGER drop_partion_on_delete_service AFTER DELETE ON services FOR EACH ROW EXECUTE PROCEDURE drop_partion_on_delete_service();
REVOKE ALL ON SCHEMA dalibo FROM PUBLIC;
REVOKE ALL ON SCHEMA dalibo FROM yang;
GRANT ALL ON SCHEMA dalibo TO yang;
GRANT USAGE ON SCHEMA dalibo TO doku_yang;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;
SET search_path = dalibo, pg_catalog;
REVOKE ALL ON FUNCTION pg_taille_jolie(p_valeur bigint, OUT v_jolie text) FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_taille_jolie(p_valeur bigint, OUT v_jolie text) FROM yang;
GRANT ALL ON FUNCTION pg_taille_jolie(p_valeur bigint, OUT v_jolie text) TO yang;
GRANT ALL ON FUNCTION pg_taille_jolie(p_valeur bigint, OUT v_jolie text) TO PUBLIC;
GRANT ALL ON FUNCTION pg_taille_jolie(p_valeur bigint, OUT v_jolie text) TO postgres;
GRANT ALL ON FUNCTION pg_taille_jolie(p_valeur bigint, OUT v_jolie text) TO doku_yang;
REVOKE ALL ON FUNCTION variation_taille_service(p_hostname text, p_service text, p_label text, p_tstamp_debut timestamp with time zone, p_duree interval, OUT v_compteur_debut numeric, OUT v_compteur_fin numeric, OUT v_compteur_delta numeric, OUT v_type_corr text, OUT v_corr double precision, OUT v_taille_un_mois numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION variation_taille_service(p_hostname text, p_service text, p_label text, p_tstamp_debut timestamp with time zone, p_duree interval, OUT v_compteur_debut numeric, OUT v_compteur_fin numeric, OUT v_compteur_delta numeric, OUT v_type_corr text, OUT v_corr double precision, OUT v_taille_un_mois numeric) FROM yang;
GRANT ALL ON FUNCTION variation_taille_service(p_hostname text, p_service text, p_label text, p_tstamp_debut timestamp with time zone, p_duree interval, OUT v_compteur_debut numeric, OUT v_compteur_fin numeric, OUT v_compteur_delta numeric, OUT v_type_corr text, OUT v_corr double precision, OUT v_taille_un_mois numeric) TO yang;
GRANT ALL ON FUNCTION variation_taille_service(p_hostname text, p_service text, p_label text, p_tstamp_debut timestamp with time zone, p_duree interval, OUT v_compteur_debut numeric, OUT v_compteur_fin numeric, OUT v_compteur_delta numeric, OUT v_type_corr text, OUT v_corr double precision, OUT v_taille_un_mois numeric) TO PUBLIC;
GRANT ALL ON FUNCTION variation_taille_service(p_hostname text, p_service text, p_label text, p_tstamp_debut timestamp with time zone, p_duree interval, OUT v_compteur_debut numeric, OUT v_compteur_fin numeric, OUT v_compteur_delta numeric, OUT v_type_corr text, OUT v_corr double precision, OUT v_taille_un_mois numeric) TO doku_yang;
SET search_path = public, pg_catalog;
REVOKE ALL ON FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, pmin numeric, pmax numeric, pwarning numeric, pcritical numeric, punit text) FROM PUBLIC;
REVOKE ALL ON FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, pmin numeric, pmax numeric, pwarning numeric, pcritical numeric, punit text) FROM yang;
GRANT ALL ON FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, pmin numeric, pmax numeric, pwarning numeric, pcritical numeric, punit text) TO yang;
GRANT ALL ON FUNCTION insert_record(phostname text, ptimet bigint, pservice text, pservicestate text, plabel text, pvalue numeric, pmin numeric, pmax numeric, pwarning numeric, pcritical numeric, punit text) TO PUBLIC;
REVOKE ALL ON TABLE services FROM PUBLIC;
REVOKE ALL ON TABLE services FROM yang;
GRANT ALL ON TABLE services TO yang;
GRANT SELECT ON TABLE services TO doku_yang;
