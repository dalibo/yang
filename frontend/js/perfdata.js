function printGraph(graphid, services, from, to) {

	$('#' + graphid).html('<img src="css/images/loading.gif" alt="[loading]" title="loading" />');

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
					},
					selection: { mode: "x" }
				});
			}
	});

}
