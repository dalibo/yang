<?php
$title = 'Known hosts';

require('./intro.php');

$query = "SELECT hostname, warnings, criticals, pg_serv, sys_serv, srv_serv, all_serv, (t.load).timet AS last_time_load, (t.load).value AS load
FROM (
	SELECT hostname, sum(warning_status::int) AS warnings, sum(critical_status::int) AS criticals,
		sum((substr(service, 1, 5) = 'PGSQL')::int) AS pg_serv,
		sum((substr(service, 1, 5) = 'SYSTM')::int) AS sys_serv,
		sum((substr(service, 1, 5) = 'SERVC')::int) as srv_serv,
		count(service) AS all_serv, get_last_value(hostname, 'SYSTM - Load', 'load1') AS load
	FROM (SELECT hostname, service, bool_or(state = 'WARNING') AS warning_status, bool_or(state = 'CRITICAL') AS critical_status FROM services GROUP BY 1,2) t2
	WHERE hostname NOT LIKE 'gateway-%'
	GROUP BY 1
	ORDER BY 1
) AS t";

$res = pg_query($dbh, $query);

if ($res === false)
	die ("Query for hosts failed.\n");

print_htmlheader($title);

require('./menu.php');

printf("<h1>%s</h1>", htmlentities($title));

while ($host = pg_fetch_array($res)) {

	if ($host['criticals'] > 0)
		$host_status_class = 'critical';
	else if ($host['warnings'] > 0)
		$host_status_class = 'warning';
	else
		$host_status_class = '';

	printf("<div><h2><a href=\"services.php?hostname=%s\" class=\"%s\">%s</a></h2>\n",
		htmlentities($host['hostname']), $host_status_class,
		htmlentities($host['hostname'])
    );

	printf("<p>%u devices monitored - %u system, %u PostgreSQL, %u others,
		<span class=\"%s\">%u warnings</span>, <span class=\"%s\">%u criticals</span></p>\n",
		$host['all_serv'], $host['sys_serv'], $host['pg_serv'], $host['srv_serv'],
		($host['warnings'] > 0)? 'warning':'', $host['warnings'],
		($host['criticals'] > 0)? 'critical':'', $host['criticals']
    );

    if (!empty($host['load']))
		printf("<p>Load: %s (last update %s).</p>\n",
			htmlentities($host['load']), htmlentities($host['last_time_load'])
		);
}

require('./outro.php');
?>
