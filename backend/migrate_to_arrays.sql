\t on
\a
\o /tmp/script
WITH t1 as (SELECT relname as tbl, relname || '_tmp' as tbltmp from pg_class where relname ~ '^counters_detail_' and relkind = 'r') 
select 'CREATE TABLE ' || tbltmp || '(date_records date, records counters_detail[]); INSERT INTO ' || tbltmp || ' SELECT date_trunc(''day'',timet),array_agg(row(timet,value)::counters_detail) FROM '|| tbl || ' GROUP BY date_trunc(''day'',timet); DROP TABLE ' || tbl ||'; ALTER TABLE ' ||  tbltmp || ' RENAME TO '|| tbl || ';' from t1;
\o
\i /tmp/script
