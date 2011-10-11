<?php
header('Content-Type: application/json');

require('./intro.php');

$services = $_POST['services'];

/* javascript timestamps are in millisecondes */
/* we can not divide (int)value/1000 cause timestamps are
 * out-of-bounds INTs in PHP, so we substr */

if (isset($_POST['from']))
	$from = substr($_POST['from'],0,-3);
else
	$from = $serie['min_timestamp'];

if (isset($_POST['to']))
	$to = substr($_POST['to'],0,-3);
else
	$to = time(); // we get the current timestamp

$values = array();

/**
 * loop on all available series for this service
 **/
 $i=0;
foreach ($services as $serie) {

	$values['graphs'][$i] = array(
		'label' => $serie['label'],
		'data' => array()
	);
	$values['map'][$serie['label']] = $i;

	$_from = ($from < $serie['min_timestamp']) ? $serie['min_timestamp'] : $from;

	$query = sprintf('SELECT extract(epoch from timet) as timet, value FROM get_sampled_service_data(%d, %s, %s, %u) ORDER BY 1',
		$serie['id'],
		sprintf('to_timestamp(%u)', $_from),
		sprintf('to_timestamp(%u)', $to),
		intval(($to - $_from) / ($conf['graph_width'] / 2))
	);

	$res = pg_query($query);
	if ($res === false)
		die (json_encode(array('error' => "Can not fetch values for hostname '{$hostname}' service '{$service}' value '{$serie['id']}'.\n")));

	/* feed the value array for this serie */
	while ($_value = pg_fetch_array($res, null, PGSQL_NUM)) {
		/* javascript timestamps are in millisecond, not second */
		$_value[0] *= 1000;
		$values['graphs'][$i]['data'][] = $_value;
	}
	$i++;
}

echo json_encode($values);

pg_close($dbh);
?>
