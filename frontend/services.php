<?php
require('./intro.php');

$hostname = $_GET['hostname'];
$title="Host '{$hostname}'";

$query = sprintf("SELECT service, label, bool_or(state = 'WARNING') OVER (PARTITION BY service) AS warning_status, bool_or(state = 'CRITICAL') OVER (PARTITION BY service) AS critical_status
FROM services
WHERE hostname = '%s'
GROUP BY 1,2,state
ORDER BY 1,2;", pg_escape_string($hostname));

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
	
	printf("<a href=\"#%s\" name=\"%s\" class=\"details\">[show details]</a>&nbsp;\n",
		htmlentities($service['service']), 
		htmlentities($service['service'])
	);

	printf("<a href=\"service.php?hostname=%s&service=%s&show=\" class=\"%s\" >%s</a>&nbsp;\n",
		htmlentities($hostname),
		htmlentities($service['service']),
		$class_state,
		htmlentities($service['service'])
	);

	printf("(<a href=\"service.php?hostname=%s&service=%s\">multi graphs</a>)\n",
		htmlentities($hostname), 
		htmlentities($service['service'])
	);

	printf("(<a href=\"service_scale.php?hostname=%s&service=%s\">scale graphs</a>)\n",
		htmlentities($hostname), 
		htmlentities($service['service'])
	);

	echo "<ul>";

	do { 
		echo "<li>";
		printf("<a href=\"service.php?hostname=%s&service=%s&show=%s\">%s</a>\n",
			htmlentities($hostname), 
			htmlentities($service['service']), 
			htmlentities($service['label']),
			htmlentities($service['label'])
		);
		echo "</li>";
		$service = pg_fetch_array($res);
	} while ($current === $service['service']);

	echo "</ul>";
}

echo "</table>\n";

?>

<script type="text/javascript">
	$('ul').hide();
	$('div#bread ul').show();
	$('a.details').toggle(
		function () {
			$(this).nextAll('ul').show();
			$(this).text('[hide details]');
		},
		function () {
			$(this).nextAll('ul').hide();
			$(this).text('[show details]');
		}
	);
</script>

<?php

require('./outro.php');
?>
