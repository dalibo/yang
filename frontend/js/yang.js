function drawGraph(data, drawLegend) {
	var confLegend = {};

	if (drawLegend == true)
		confLegend = {
			container: $('#legend'),
			labelFormatter: function(label, series) {
				return '<label for="id' + label + '">'
					+ '<input type="checkbox" name="'+ label +'" checked="checked" id="id'+ label +'" />'
					+ label + '</label>';
			}
		};
	else
		confLegend = {
			show: false
		};
	
	$.plot(
		$('#graph'), 
		data,
		{
			legend: confLegend,
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
}

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
			// hardcode the colors so they don't shift
			// when [un]checking
			var i = 0;
			$.each(data.graphs, function(key, val) {
				val.color = i;
				++i;
			});

			// save the data in the jQuery namespace
			jQuery.yang.data = data;
			
			drawGraph(jQuery.yang.data.graphs, true);

			$('#legend').find("input").click(plotAccordingToChoices);

			$('#fromdate').attr('value', $.datepicker.formatDate('dd/mm/yy', new Date(parseInt(from))));
			$('#todate').attr('value', $.datepicker.formatDate('dd/mm/yy', new Date(parseInt(to))));
		}
	});
}

function plotAccordingToChoices() {
	var data = [];

	$("#legend").find("input:checked").each(function () {
		var key = $(this).attr("name");
		if (key && jQuery.yang.data.graphs[jQuery.yang.data.map[key]])
		data.push(jQuery.yang.data.graphs[jQuery.yang.data.map[key]]);
	});

	if (data.length > 0)
		drawGraph(data, false);
}
