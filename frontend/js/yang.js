function printGraph(graphid, services, from, to) {

	$('#' + graphid).html('<img src="css/images/loading.gif" alt="[loading]" title="loading" />');

	var tick_size = [5, 'second'];
	var interval = to - from;
	var unit = 'year';
	var freq = 1;
	/* 6 minutes */
	if (interval < 360000) {
		unit = 'second';
		freq = parseInt(interval/6000);
	}
	/* 6 hour */
        else if (interval <= 21600000) {
                unit = 'minute';
		freq = parseInt(interval/360000);
        }
	/* 6 day */
        else if (interval <= 518400000) {
                unit = 'hour';
		freq = parseInt(interval/21600000);
        }
	/* 6 month */
        else if (interval < 15552000000) {
                unit = 'day';
		freq = parseInt(interval/518400000);
        }
	/* 6 year */
        else if (interval < 189216000000) {
                unit = 'month';
		freq = parseInt(interval/15552000000);
        }
        else {
                unit = 'year';
		freq = parseInt(interval/189216000000);
        }

	tick_size = [freq, unit];

	$.ajax({
		type: 'POST',
		contentType: 'application/x-www-form-urlencoded',
		url: 'service_jsdata.php',
		cache: false,
		dataType: 'json',
		data: {
			services: services,
			from: from,
			to: to
		},
		success: function (data) {
			plot = $.plot(
				$('#' + graphid), 
				data.graphs,
				{
					legend: {
						container: $('#legend' + graphid)
					},
					xaxis: {
						mode: 'time',
						tickSize: tick_size
					},
					yaxis: {
						tickFormatter: function (val, axis) {
							if (val > 1000000000000)
								return (val / 1000000000000).toFixed(axis.tickDecimals) + " T" + services[0].unit;
							if (val > 1000000000)
								return (val / 1000000000).toFixed(axis.tickDecimals) + " G" + services[0].unit;
							if (val > 1000000)
								return (val / 1000000).toFixed(axis.tickDecimals) + " M" + services[0].unit;
							else if (val > 1000)
								return (val / 1000).toFixed(axis.tickDecimals) + " k " + services[0].unit;
							else
								return val.toFixed(axis.tickDecimals) + " " + services[0].unit;
						},
						tickDecimals: 2
					},
					series: {
						lines: { show: true },
					},
					selection: {
						mode: "x",
						color: "#444"
					}
				});

			$('#fromdate').attr('value', $.datepicker.formatDate('dd/mm/yy', new Date(parseInt(from))));
			$('#todate').attr('value', $.datepicker.formatDate('dd/mm/yy', new Date(parseInt(to))));
		}
	});

}
