<?php
require('./intro.php');

/**
 * @param $graphid NOT html-escaped here !!
 **/
function print_graph($title, $graphid, $data) {
	
	?>
	<div id="graph<?php echo $graphid ?>" style="width:400px;height:200px;"></div>
	<p><div id="legend<?php echo $graphid ?>"></div></p>

	<script type="text/javascript">
		$(document).ready(function () {
			$.plot(
				$('#graph<?php echo $graphid ?>'), 
				<?php echo json_encode($data); ?>,
				{
					legend: {
						container: $('#legend<?php echo $graphid ?>')
					},
					xaxis: {
						mode: 'time',
						timeformat: '%d/%m %Hh'
					},
					yaxis: {
						tickFormatter: function (val, axis) {
							if (val > 1000000000000)
								return (val / 1000000000000).toFixed(axis.tickDecimals) + " T<?php echo $serie['unit'] ?>";
							if (val > 1000000000)
								return (val / 1000000000).toFixed(axis.tickDecimals) + " G<?php echo $serie['unit'] ?>";
							if (val > 1000000)
								return (val / 1000000).toFixed(axis.tickDecimals) + " M<?php echo $serie['unit'] ?>";
							else if (val > 1000)
								return (val / 1000).toFixed(axis.tickDecimals) + " k<?php echo $serie['unit'] ?>";
							else
								return val.toFixed(axis.tickDecimals) + " <?php echo $serie['unit'] ?>";
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

function graph_on_period($series, $period)
{
    $values = array();

    pg_result_seek($series, 0);
    
    /**
     * loop on all available series for this service
     **/
    $i = 0;
    while (($serie = pg_fetch_array($series)) !== false) {
    
    	$values[$i] = array();
    		
    	$values[$i]['label'] = $serie['label'];
    	$values[$i]['data'] = array();
    
    	/* Query for values of the current service serie */
    	$query = sprintf("SELECT extract(epoch FROM timet::timestamp), value 
    		FROM counters_detail_%d 
    		WHERE timet > now() - '%s'::interval
    		ORDER BY timet;", $serie['id'], $period
    	);

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
    
    print_graph("{$service}", ereg_replace(' ', '', $period), $values);
}

$hostname = $_GET['hostname'];
$service = $_GET['service'];
$title = "Host '{$hostname}', service '{$service}'";

/** 
 * build the query to fetch available series for this service 
 **/

$query = sprintf("SELECT id, service, label, unit
FROM services
WHERE hostname='%s'
	AND service='%s'
ORDER BY label", pg_escape_string($hostname), pg_escape_string($service));

$series = pg_query($query);

if ($series === false)
  die ("Can not fetch service values for hostname '{$hostname}' service '{$service}'.\n");

print_htmlheader($title);

require('./menu.php');

printf("<h1>%s</h1>", htmlentities($title));

printf("<h2>One day interval</h2>\n");
graph_on_period($series, '1 day');
printf("<h2>One week interval</h2>\n");
graph_on_period($series, '1 week');
printf("<h2>One month interval</h2>\n");
graph_on_period($series, '1 month');
printf("<h2>One year interval</h2>\n");
graph_on_period($series, '1 year');

require('./outro.php');
?>
