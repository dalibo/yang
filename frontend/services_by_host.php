<?php
require('./intro.php');

ini_set('display_errors', 1);

function print_graph($graphid, $data) {
	
    $unit = $data['unit'];
    unset($data['unit']);

	?>

	<div id="graph<?php echo $graphid ?>" style="width:600px;height:300px;"></div>
        <div id="legend<?php echo $graphid ?>"></div>
	<div style="clear: left;">&nbsp;</div>

	<script type="text/javascript">
		$(document).ready(function () {
			$.plot(
				$('#graph<?php echo $graphid ?>'), 
				<?php echo json_encode($data); ?>,
				{
					legend: {
   				    container: $('#legend<?php echo $graphid ?>'),
					    noColumns: 2
					},
					xaxis: {
						mode: 'time',
						timeformat: '%d/%m %Hh'
					},
                                        yaxis: {
						tickFormatter: function (val, axis) {
							if (val > 1000000000000)
								return (val / 1000000000000).toFixed(axis.tickDecimals) + " T<?php echo $unit ?>";
							if (val > 1000000000)
								return (val / 1000000000).toFixed(axis.tickDecimals) + " G<?php echo $unit ?>";
							if (val > 1000000)
								return (val / 1000000).toFixed(axis.tickDecimals) + " M<?php echo $unit ?>";
							else if (val > 1000)
								return (val / 1000).toFixed(axis.tickDecimals) + " k<?php echo $unit ?>";
							else
								return val.toFixed(axis.tickDecimals) + " <?php echo $unit ?>";
						},
						tickDecimals: 2
					},
					series: {
						lines: { show: true },
						/*points: { show: true }*/
					}
				}
			);
		});
	</script>

	<?php
}

function graph_on_period($service, $series, $period)
{
    $values = array();

    pg_result_seek($series, 0);

    /* compute timestamps for the period */
    $rqp = pg_query(sprintf("SELECT extract(epoch FROM NOW() - interval '%s') AS from,
extract(epoch FROM NOW()) AS to;", pg_escape_string($period)));

    if ($rqp === false)
	die ("Cannot compute timestamps from period: {$period}\n");

    $row = pg_fetch_row($rqp);

    /* echo "<pre>"; */
    /* var_dump($row); */
    /* echo "</pre>"; */

    pg_free_result($rqp);

    $from = $row[0];
    $to = $row[1];

    /**
     * loop on all available series for this service
     **/
    $i = 0;
    while (($serie = pg_fetch_array($series)) !== false) {

    	$values[$i] = array();

	$values['unit'] = $serie['unit'];
    	$values[$i]['label'] = $serie['label'];
    	$values[$i]['data'] = array();

    	/* Query for values of the current service serie */
	$query = sprintf('SELECT extract(epoch from timet) as timet, value FROM get_sampled_service_data(%d, %s, %s, %u) ORDER BY 1',
			 $serie['id'],
			 sprintf('to_timestamp(%u)', $from),
			 sprintf('to_timestamp(%u)', $to),
			 intval(($to - $from) / 600 / 2)
	);


    	/* $query = sprintf("SELECT extract(epoch FROM timet::timestamp), value  */
    	/* 	FROM counters_detail_%d  */
    	/* 	WHERE timet > now() - '%s'::interval */
    	/* 	ORDER BY timet;", $serie['id'], $period */
    	/* ); */

    	$res = pg_query($query);
    	if ($res === false)
    		die ("Can not fetch values for hostname '{$hostname}' service '{$service}' value '{$serie['id']}'.\n");
    
    	/* feed the value array for this serie */
    	while ($_value = pg_fetch_array($res, null, PGSQL_NUM)) {
    		/* javascript timestamps are in millisecond, not second */
    		$_value[0] *= 1000;
    		$values[$i]['data'][] = $_value;
    	}

    	$i++;
    }

    return $values;
    
}

$hostname = $_GET['hostname'];
if (isset($_GET['interval'])) {
    $interval = $_GET['interval'];
} else {
    $interval = 'week';
}
$title = "Host '{$hostname}'";

/* get all the services of the host */
$qsr = sprintf("SELECT service FROM services WHERE hostname = '%s' GROUP BY 1 ORDER BY 1",
	      pg_escape_string($hostname));

$res = pg_query($qsr);
if ($res === false)
    die ("Cannot fetch services for hostname '{$hostname}'.\n");

$services = array();
while (($s = pg_fetch_array($res)) !== false) {
    $services[] = $s['service'];
}

pg_free_result($res);

print_htmlheader($title);

require('./menu.php');

/* zoom presets */
?>
<div id"#presets">
  <a href="services_by_host.php?hostname=<?php echo htmlentities($hostname) ?>&interval=day">day</a>
  <a href="services_by_host.php?hostname=<?php echo htmlentities($hostname) ?>&interval=week">week</a>
  <a href="services_by_host.php?hostname=<?php echo htmlentities($hostname) ?>&interval=month">month</a>
  <a href="services_by_host.php?hostname=<?php echo htmlentities($hostname) ?>&interval=year">year</a>
</div>

<?php
/* for each service get the series */
foreach ($services as $i => $service) {
    $qse = sprintf("SELECT id, service, label, unit
FROM services
WHERE hostname = '%s'
  AND service='%s'
ORDER BY label", pg_escape_string($hostname), pg_escape_string($service));

    $series = pg_query($qse);
    if ($series === false)
	die ("Can not fetch services for hostname '{$hostname}'.\n");

    $sd = graph_on_period($service, $series, '1 '.$interval);

    printf("<h2>%s</h2>", htmlentities($service));

    printf("<p><a href=\"service.php?hostname=%s&service=%s\">Details</a></p>\n",
           htmlentities($hostname),
           htmlentities($service)
        );


    print_graph($i, $sd);

    pg_free_result($series);
}

require('./outro.php');
?>