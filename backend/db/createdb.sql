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
-- Name: plperl; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: postgres
--

CREATE PROCEDURAL LANGUAGE plperl;


ALTER PROCEDURAL LANGUAGE plperl OWNER TO postgres;

--
-- Name: plperlu; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: postgres
--

CREATE PROCEDURAL LANGUAGE plperlu;


ALTER PROCEDURAL LANGUAGE plperlu OWNER TO postgres;

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


ALTER FUNCTION public.get_last_value(i_hostname text, i_service text, i_label text) OWNER TO nagios_perfdata;

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
-- Name: insert_record(text, bigint, text, text, numeric, text); Type: FUNCTION; Schema: public; Owner: nagios_perfdata
--

CREATE FUNCTION insert_record(hostname text, timet bigint, service text, label text, value numeric, unit text) RETURNS boolean
    LANGUAGE plperlu
    AS $_X$
# This function inserts a record into its table
# It also maintains meta data (and CHECKS metadata)

my ($hostname,$timet,$service,$label,$value,$unit)=@_;

# First, it this hostname/service/label already in our local cache ?
if (not defined $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"})
{
        # It isn't in cache
        # Is it known in the database ?
        my $prepstt=spi_prepare('SELECT id,hostname,service,label,unit,extract(epoch from last_modified) as lastm FROM services WHERE hostname=$1 and service=$2 and label=$3'
                    , 'text', 'text', 'text');
        my $result=spi_exec_prepared($prepstt,$hostname,$service,$label);
        spi_freeplan($prepstt);

        if (not defined $result->{rows}[0])
        {
                # We create the record
                my $prepstt=spi_prepare('INSERT INTO services (hostname,service,label,unit) VALUES($1,$2,$3,$4)'
                                    , 'text', 'text', 'text', 'text');
                my $result=spi_exec_prepared($prepstt,$hostname,$service,$label,$unit);
                ($rv->{status} == SPI_OK_INSERT) or elog(ERROR,"Can't insert <$hostname,$service,$label,$unit>");
                spi_freeplan($prepstt);

                # It's in the database
                # Let's retrieve it
                $prepstt=spi_prepare('SELECT id,hostname,service,label,unit,extract(epoch from last_modified) as lastm FROM services WHERE hostname=$1 and service=$2 and label=$3'
                                    , 'text', 'text', 'text');
                $result=spi_exec_prepared($prepstt,$hostname,$service,$label);
                spi_freeplan($prepstt);
                # Put it in the cache
                $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{ID}= $result->{rows}[0]->{id};
                $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{UNIT}= $result->{rows}[0]->{unit};
                $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{LAST_M}= $result->{rows}[0]->{lastm};
        }
        else
        {
                # Just put it in the cache
                $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{ID}= $result->{rows}[0]->{id};
                $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{UNIT}= $result->{rows}[0]->{unit};
                $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{LAST_M}= $result->{rows}[0]->{lastm};
        }
}
# It is in the cache. So just double check the metadata : is the unit OK. Else we'll die for now as we're still debugging
($_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{UNIT} eq $unit)
   or elog(ERROR,"Inconsistent unit : $hostname,$timet,$service,$label,$value,$unit. Unit is different in the DB");

my $id = $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{ID};

# Is service's last modified date older than a day ? We have to update service table if its the case.
if ($_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{LAST_M}= $result->{rows}[0]->{lastm} + 86400 <= time() )
{
        # Lets update
        my $prepstt=spi_prepare('UPDATE services set last_modified=now()::date WHERE id=$1','bigint');
        my $result=spi_exec_prepared($prepstt,$id);
        # No need to update cache. The session is closed after each insertion batch, so the cache will be refreshed then
}


# We don't need to create the counters partition. There is a trigger doing this work for us as soon as we insert a new record in service
# There is also a trigger to destroy the partition when its record is removed from services

# Do we already have a prepared insert statement for this table ?
if (not defined $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{PREP_STT_I})
{
        my $prepstt=spi_prepare("INSERT INTO counters_detail_${id} (timet,value) VALUES ('epoch'::timestamptz + \$1 * '1 second'::interval,\$2)",'bigint','numeric');
        $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{PREP_STT_I}=$prepstt;
}
my $prepstt=$_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{PREP_STT_I};

# Now insert the data: We have to eval it, it may fail.
eval{spi_exec_prepared($prepstt,$timet,$value);};

# Eval failed. We have to update instead
if ($@)
{
        # Do we already have a prepared insert statement for this table ?
        if (not defined $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{PREP_STT_U})
        {
                my $prepstt=spi_prepare("UPDATE counters_detail_${id} SET value = \$2 WHERE timet='epoch'::timestamptz + \$1 * '1 second'::interval",'bigint','numeric');
                $_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{PREP_STT_U}=$prepstt;
        }
        my $prepstt=$_SHARED{KNOWN_HOSTS}->{"$hostname/$service/$label"}->{PREP_STT_U};

        # Now insert the data. If it fails, let the whole thing die
        spi_exec_prepared($prepstt,$timet,$value);

}
return 1;

$_X$;


ALTER FUNCTION public.insert_record(hostname text, timet bigint, service text, label text, value numeric, unit text) OWNER TO nagios_perfdata;

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


ALTER FUNCTION public.max_timet_id(p_id bigint) OWNER TO postgres;

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


ALTER FUNCTION public.min_timet_id(p_id bigint) OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: services; Type: TABLE; Schema: public; Owner: nagios_perfdata; Tablespace: 
--

CREATE TABLE services (
    id bigint NOT NULL,
    hostname text,
    service text,
    label text,
    unit text,
    last_modified date DEFAULT (now())::date,
    creation_timestamp timestamp with time zone DEFAULT now()
);


ALTER TABLE public.services OWNER TO nagios_perfdata;

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

