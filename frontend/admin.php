<?php
$title = 'Services Admin by Host';

require('./intro.php');

require('./menu.php');

/* Delete a service */
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
}

/* main query */
$query = 'SELECT hostname, service, label, to_char(creation_timestamp, \'yyyy-mm-dd HH24:MI\') AS creation_timestamp,  last_modified, id
FROM services ORDER BY';

/* sort control */
if (!isset($_SESSION['admin']))
	$_SESSION['admin'] = array(
		'sort' => array(
			0 => array(1,'ASC'),
			1 => array(2,'ASC'),
			2 => array(3,'ASC'),
			3 => array(4,'ASC'),
			4 => array(5,'ASC')
		)
	);

/* custom ordering */
if (isset($_POST['sort'])) {
	$used_col = array(1=>false,2=>false,3=>false,4=>false,5=>false);
	$_SESSION['admin']['sort'] = array(); // erase past order
	$i=0;
	foreach ($_POST['sort'] as $col) {
		if (($used_col[$col] === false) && ($col !== '')) { // remove duplicate
			$_SESSION['admin']['sort'][] = array(
				intval($col), pg_escape_string($_POST['sortorder'][$i])
			);
			$used_col[$col] = true;
		}
		$i++;
	}
}

print_htmlheader($title);

printf("<h1>%s</h1>", htmlentities($title));

$sort_options = '
<option value="">--</option>
<option value="1"%s>Host</option>
<option value="2"%s>Service</option>
<option value="3"%s>Label</option>
<option value="4"%s>Creation date</option>
<option value="5"%s>Last update</option>
';

$sortorder_options = '
<option value="">--</option>
<option value="ASC"%s>ASC</option>
<option value="DESC"%s>DESC</option>
';

/* build the query sort order and print the sort form */
if (empty($_SESSION['admin']['sort'])) $query .= '1,2,3,4,5';
else {

	$sort = array(0,0,0,0,0);
	$sortoder = array('','','','','');

	$i=0;
	foreach ($_SESSION['admin']['sort'] AS $c) {
		$query .= sprintf(' %d %s,', $c[0], $c[1]);
		$sort[$i] = $c[0];
		$sortorder[$i] = $c[1];
		$i++;
	}

	$query = substr($query, 0, -1); // remove the last comma
}

echo "<form action=\"?\" method=\"post\">\n";
for ($i=0; $i < 5; $i++) {
	printf("<select name=\"sort[]\">{$sort_options}</select>",
		($sort[$i] === 1)? ' selected="selected"':'',
		($sort[$i] === 2)? ' selected="selected"':'',
		($sort[$i] === 3)? ' selected="selected"':'',
		($sort[$i] === 4)? ' selected="selected"':'',
		($sort[$i] === 5)? ' selected="selected"':''
	);
	printf("<select name=\"sortorder[]\">{$sortorder_options}</select>&nbsp;&nbsp;&nbsp;",
		($sortorder[$i] === 'ASC')? ' selected="selected"':'',
		($sortorder[$i] === 'DESC')? ' selected="selected"':''
	);
}
echo "<input type=\"submit\" name=\"doSort\" value=\"Sort &gt;\" />";
echo "</form>";

$res = pg_query($dbh, $query);

if ($res === false)
	die ("Query for hosts failed.\n");

echo "<table border=\"1\">";
echo "<tr>
	<th>Host</th>
	<th>Service</th>
	<th>Label</th>
	<th>Creation date</th>
	<th>Last update date</th>
	<th>Action</th>
</tr>\n";
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
