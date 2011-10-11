function updateGraph(from, to) {

	$('graph').html('<img src="css/images/loading.gif" alt="[loading]" title="loading" />');

	$.ajax({
		type: 'POST',
		contentType: 'application/x-www-form-urlencoded',
		url: 'service_jsdata.php',
		cache: false,
		dataType: 'json',
		data: {
			services: jQuery.yang.graph,
			from: from,
			to: to
		},
		success: function (data) {
			plot = $.plot(
				$('#graph'),
				data.graphs,
				{
					legend: {
						container: $('#legend')
					},
					xaxis: {
						mode: 'time'
					},
					yaxis: {
						tickFormatter: function (val, axis) {
							if (val > 1000000000000)
								return (val / 1000000000000).toFixed(axis.tickDecimals) + " T" + jQuery.yang.graph[0].unit;
							if (val > 1000000000)
								return (val / 1000000000).toFixed(axis.tickDecimals) + " G" + jQuery.yang.graph[0].unit;
							if (val > 1000000)
								return (val / 1000000).toFixed(axis.tickDecimals) + " M" + jQuery.yang.graph[0].unit;
							else if (val > 1000)
								return (val / 1000).toFixed(axis.tickDecimals) + " k " + jQuery.yang.graph[0].unit;
							else
								return val.toFixed(axis.tickDecimals) + " " + jQuery.yang.graph[0].unit;
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
