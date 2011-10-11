<?php
require('./intro.php');

$hostname = $_GET['hostname'];
$title="Host '{$hostname}'";

$query = sprintf("SELECT service, bool_or(state = 'WARNING') AS warning_status, bool_or(state = 'CRITICAL') AS critical_status
FROM services
WHERE hostname = 'argus_audio'
GROUP BY 1
ORDER BY 1,2
", pg_escape_string($hostname));

$res = pg_query($query);
if ($res === false)
  die ("Can not fetch services for hostname '{$hostname}'.\n");
  
print_htmlheader($title);

require('./menu.php');

printf("<h1>%s</h1>", htmlentities($title));

echo "<table>\n";

$current = '';
$service = pg_fetch_array($res);

while ($service !== false) {
	$current = $service['service'];
	if ($service['critical_status'] == 't')
	    $class_state = 'critical';
	else if ($service['warning_status'] == 't')
	    $class_state = 'warning';
	else
	    $class_state = '';

	echo "<tr>\n<td>\n";

	printf("<a href=\"service.php?hostname=%s&service=%s\" class=\"%s\" >%s</a>&nbsp;\n",
		htmlentities($hostname),
		htmlentities($service['service']),
		$class_state,
		htmlentities($service['service'])
	);

	printf("(<a href=\"service_scale.php?hostname=%s&service=%s\">scale graphs</a>)\n",
		htmlentities($hostname), 
		htmlentities($service['service'])
	);
	$service = pg_fetch_array($res);
}

echo "</table>\n";
require('./outro.php');
?>
