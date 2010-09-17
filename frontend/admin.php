<?php
$title = 'Services Admin by Host';

require('./intro.php');

require('./menu.php');

if (isset($_GET['action']) and isset($_GET['serviceid']) and (! empty($_GET['serviceid']))) {
	
	$query = sprintf('DELETE FROM services WHERE id = %u', $_GET['serviceid']);
	$res = pg_query($dbh, $query);
	
	$res = pg_affected_rows($res);
	if ($res > 0) {
		echo "<pre style=\"color: blue\">Service {$_GET['serviceid']} deleted.</pre>";
	}
	else {
		echo "<pre style=\"color: blue\">Couldn't delete the service {$_GET['serviceid']} !</pre>";
	}
	
	exit;
}

$query = 'SELECT id, hostname, service, label, to_char(creation_timestamp, \'yyyy-mm-dd HH24:MI\') AS creation_timestamp,  last_modified
FROM services 
ORDER BY 2,3,4';
$res = pg_query($dbh, $query);

if ($res === false)
	die ("Query for hosts failed.\n");

print_htmlheader($title);

printf("<h1>%s</h1>", htmlentities($title));

$lasthost = $lastservice = '';

/*
echo "<ul>";
$host = pg_fetch_array($res);
while ($host) {

	if ($lasthost != $host['hostname']) {
		$lasthost = $host['hostname'];
		printf("<li> <h2>%s</h2>", htmlentities($host['hostname']));
		echo "<ul>";
		while ($lasthost == $host['hostname']) {
			if ($lastservice != $host['service']) {
				$lastservice = $host['service'];
				printf("<li> <h3>%s</h3>", htmlentities($host['service']));
				echo "<ul>";
				while ($lastservice == $host['service']) {
					printf("<li> <h4>%s</h4>Created: %s, last modified date: %s<br /><a class=\"delete\" href=\"?action=del&serviceid=%d\">[delete]</a></li>",
						htmlentities($host['label']),
						htmlentities($host['creation_timestamp']),
						htmlentities($host['last_modified']),
						htmlentities($host['id'])
					);
					$host = pg_fetch_array($res);
				}
				echo "</ul>";
				echo "</li>";
			}
		}
		echo "</ul>";
		echo "</li>";
	}
}
echo "</ul>";
*/
echo "<table border=\"1\">";
echo "<tr><th>Host</th><th>Service</th><th>Label</th><th>Creation date</th><th>Last update date</th><th>Action</th></tr>\n";
while ($host = pg_fetch_array($res)) {
	echo "<tr>\n";
	printf('<td>%s</td>', htmlentities($host['hostname']));
	printf('<td>%s</td>', htmlentities($host['service']));
	printf('<td>%s</td>', htmlentities($host['label']));
	printf('<td>%s</td>', htmlentities($host['creation_timestamp']));
	printf('<td>%s</td>', htmlentities($host['last_modified']));
	printf('<td><a class="delete" href="?action=del&serviceid=%d">[delete]</a></td>', $host['id']);
	echo "</tr>\n";
}
echo "</table>";
?>

<script type="text/javascript">
	$(document).ready(function () {
		$('.delete').click(function() {
			var trs = $(this).closest('tr').children('td');
			if (confirm('are you sure you want to delete label "'+ trs[2].innerHTML +
				'" from service "'+ trs[1].innerHTML +
				'" host "'+ trs[0].innerHTML +'" ?')
			)
				return true;
				
			return false;
		});
	});
</script>

<?php 

require('./outro.php');
?>
