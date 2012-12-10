\t on
\a
\o /tmp/script
WITH t1 as (SELECT relname as tbl, relname || '_tmp' as tbltmp from pg_class where relname ~ '^counters_detail_') 
select 'CREATE TABLE ' || tbltmp || '(records counters_detail[]); INSERT INTO ' || tbltmp || ' date_trunc(''day'',timet),select array_agg(row(timet,value)::counters_detail) from '|| tbl || ' group by date_trunc(''day'',timet); DROP TABLE ' || tbl ||'; ALTER TABLE ' ||  tbltmp || ' RENAME TO '|| tbl || ';' from t1;
\o
\i /tmp/script
