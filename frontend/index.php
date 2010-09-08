<?php
$title = 'Known hosts';

require('./intro.php');

$query = "SELECT hostname, count(distinct service) AS services
FROM services
WHERE hostname NOT LIKE 'gateway-%'
GROUP BY hostname
ORDER BY hostname";

$res = pg_query($dbh, $query);

if ($res === false)
	die ("Query for hosts failed.\n");

print_htmlheader($title);

require('./menu.php');

printf("<h1>%s</h1>", htmlentities($title));

while ($host = pg_fetch_array($res)) {
    // get last available load
    $loadquery = "SELECT to_char(timet, 'YYYY-mm-DD HH:MM:SS') AS lasttime, value FROM get_last_value('".pg_escape_string($host['hostname'])."','SYSTM - Load','load1') AS (timet timestamptz, value numeric)";
    $loadres = pg_query($dbh, $loadquery);
    if (pg_num_rows($loadres) > 0)
        $load = pg_fetch_array($loadres);
    else
        $load = false;
    // get number of services
    $squery = "SELECT substr(service, 1, 5) AS service, count(*) AS total
      FROM (SELECT distinct service FROM services
            WHERE hostname='".pg_escape_string($host['hostname'])."'
              AND substr(service, 1, 5) in ('PGSQL', 'SERVC', 'SYSTM')) AS t
      GROUP BY 1";
    $sres = pg_query($dbh, $squery);
    $servcservices = 0;
    $systmservices = 0;
    $pgsqlservices = 0;
    while ($line = pg_fetch_array($sres))
    {

        if ($line['service'] == 'PGSQL')
            $pgsqlservices = $line['total'];
        else if ($line['service'] == 'SERVC')
            $servcservices = $line['total'];
        else if ($line['service'] == 'SYSTM')
            $systmservices = $line['total'];
    }

	printf("<div><h2><a href=\"services.php?hostname=%s\">%s</a></h2>\n",
		htmlentities($host['hostname']), htmlentities($host['hostname'])
    );

	printf("<p>%u devices monitored - %u system, %u PostgreSQL, %u others</p>\n",
		htmlentities($host['services']),
		htmlentities($systmservices), htmlentities($pgsqlservices), htmlentities($servcservices)
    );

    if ($load && isset($load['value']))
	    printf("<p>Load: %s (last update %s).</p>\n",
	    	htmlentities($load['value']), htmlentities($load['lasttime'])
	);
}

require('./outro.php');
?>
