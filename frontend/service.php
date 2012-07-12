<?php
require('./intro.php');

$hostname = $_GET['hostname'];
$service = $_GET['service'];
$title = "Host '{$hostname}' service '{$service}'";

/** 
 * build the query to fetch available series for this service 
 **/

/* Set the WHERE condition to filter on wanted label if given */
$where = 'TRUE';

$query = sprintf("SELECT id, service, label || ' (max: ' || pg_size_pretty(max::bigint) || ')' AS label, unit, extract(epoch FROM creation_timestamp) as creation_timestamp
FROM services
WHERE hostname='%s'
	AND service='%s'
	AND %s
ORDER BY label", pg_escape_string($hostname), pg_escape_string($service), $where);

$series = pg_query($query);

if ($series === false)
	die ("Can not fetch service values for hostname '{$hostname}' service '{$service}'.\n");

$services_info = array();

print_htmlheader($title);

require('./menu.php');

printf("<h1>%s</h1>", htmlentities($title));

/**
 * loop on all available series for this service
 **/
$i = 0;
while (($serie = pg_fetch_array($series)) !== false) {

	$services_info[$i] = array(
		'label' => $serie['label'],
		'id' => $serie['id'],
		'min_timestamp' => $serie['creation_timestamp'],
		'unit' => $serie['unit']
	);

	$i++;
}
?>
<h2>values of '<?php echo htmlentities($service) ?>'</h2>
	<div>
		<ul class="scales">
			<li><input type="button" name="interval" value="year" /></li>
			<li><input type="button" name="interval" value="month" /></li>
			<li><input type="button" name="interval" value="week" /></li>
			<li><input type="button" name="interval" value="day" /></li>
		</ul>
		<p class="scales">Custom interval&nbsp;
			<label >from:</label><input size="10" type="text" class="datepick" id="fromdate" name="fromdate" />
			<label >to:</label><input size="10" type="text" class="datepick" id="todate" name="todate" />
			<input type="button" name="interval" value="custom" />
		</p>
		<div id="graph" class="graph" style="width:<?php echo $conf['graph_width'] ?>px;height:<?php echo $conf['graph_height'] ?>px">
			<img src="css/images/loading.gif" alt="[loading]" title="loading" />
		</div>
		<p>
			<div class="legend" id="legend"></div>
		</p>

		<script type="text/javascript">
			/* used to keep track of graph id and props generated */
			$(document).ready(function () {
				jQuery.yang = {graph: <?php echo json_encode($services_info); ?>};
			});
		</script>
	</div>

	<script type="text/javascript">
		$(document).ready(function () {
			$('.scales input[type=button]').click(function () {
				var fromDate = new Date();
				var toDate = new Date();

				switch($(this).attr('value')) {
					case 'year':
						fromDate.setYear(fromDate.getYear() + 1900 - 1);
					break;
					case 'month':
						fromDate.setMonth(fromDate.getMonth() - 1);
					break;
					case 'week':
						fromDate.setDate(fromDate.getDate() - 7);
					break;
					case 'day':
						fromDate.setDate(fromDate.getDate() - 1);
					break;
					case 'custom':
						if ($('#fromdate').attr('value') === '' ) {
							alert('you must set the starting date.');
							return false;
						}

						if ($('#todate').attr('value') === '' )
							/* set the toDate to the current day */
							$('#todate').attr('value', $.datepicker.formatDate('dd/mm/yy', toDate ));
						else
							toDate = $.datepicker.parseDate('dd/mm/yy', $('#todate').attr('value'));

						fromDate = $.datepicker.parseDate('dd/mm/yy', $('#fromdate').attr('value'));
					break;
				}

				updateGraph(fromDate.getTime(), toDate.getTime());

				return false;
			})

			/* handle zoom action */
			$('div.graph').bind("plotselected", function (event, ranges) {

				// clamp the zooming to prevent eternal zoom
				if (ranges.xaxis.to - ranges.xaxis.from < 0.00001) 
					ranges.xaxis.to = ranges.xaxis.from + 0.00001;
				if (ranges.yaxis.to - ranges.yaxis.from < 0.00001) 
					ranges.yaxis.to = ranges.yaxis.from + 0.00001;
				
				updateGraph(ranges.xaxis.from.toPrecision(13), ranges.xaxis.to.toPrecision(13));
			});

			/* by default, show the week graph by triggering the week button */
			$('ul.scales input[value=week]').click();

			/* bind the datepicker to the date fields */
			$('.datepick').datepicker({
				autoFocusNextInput: true,
				showOn: 'focus',
				dateFormat: 'dd/mm/yy'
			});
		});

	</script>
<?php

require('./outro.php');
?>
