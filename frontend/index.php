<?php
$title = 'Known hosts';

require('./intro.php');

$query = "SELECT t.hostname, t.pg_serv, t.sys_serv, t.srv_serv, t.all, (t.load).timet AS last_time_load, (t.load).value AS load
FROM (
	SELECT hostname,
		sum((substr(service, 1, 5) = 'PGSQL')::int) AS pg_serv,
		sum((substr(service, 1, 5) = 'SYSTM')::int) AS sys_serv,
		sum((substr(service, 1, 5) = 'SERVC')::int) as srv_serv,
		count(service) AS all,
		get_last_value(hostname, 'SYSTM - Load', 'load1') AS load
	FROM (SELECT distinct hostname, service FROM services) t
	WHERE hostname NOT LIKE 'gateway-%'
	GROUP BY hostname
	ORDER BY 1,2
) AS t";

$res = pg_query($dbh, $query);

if ($res === false)
	die ("Query for hosts failed.\n");

print_htmlheader($title);

require('./menu.php');

printf("<h1>%s</h1>", htmlentities($title));

while ($host = pg_fetch_array($res)) {

	printf("<div><h2><a href=\"services.php?hostname=%s\">%s</a></h2>\n",
		htmlentities($host['hostname']), htmlentities($host['hostname'])
    );

	printf("<p>%u devices monitored - %u system, %u PostgreSQL, %u others</p>\n",
		$host['all'], $host['sys_serv'], $host['pg_serv'], $host['srv_serv']
    );

    if (!empty($host['load']))
		printf("<p>Load: %s (last update %s).</p>\n",
			htmlentities($host['load']), htmlentities($host['last_time_load'])
		);
}

require('./outro.php');
?>
