<?php 
require('conf/config.php');

session_start();

function stripVar(&$var) {
	if (is_array($var)) {
		foreach($var as $k => $v) {
			stripVar($var[$k]);
		}
	}
	else
		$var = stripslashes($var);
}

function print_htmlheader($title) {
	printf('<html>
		<head>
		<title>%s</title>
		<link rel="stylesheet" media="all" type="text/css" href="css/yang.css" />
		<link rel="stylesheet" media="all" type="text/css" href="css/jquery-ui.css" />

		<script type="text/javascript" src="js/jquery.js"></script>
		<script type="text/javascript" src="js/jquery.ui.core.js"></script>
		<script type="text/javascript" src="js/jquery.ui.datepicker.js"></script>
		<script type="text/javascript" src="js/jquery.flot.js"></script>
		<script type="text/javascript" src="js/jquery.flot.selection.js"></script>
		<script type="text/javascript" src="js/yang.js"></script>

		</head>
		<body>
		', htmlentities($title)
	);
}

function unitized($num=0) {
	$units = array('', 'k', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y');

	for ($i = 0; $i < 8 and $num >= 1024; $i++, $num/=1024);

	return round($num, 2) . $units[$i];
}

ini_set('magic_quotes_runtime', 0);
ini_set('magic_quotes_sybase', 0);

if (ini_get('magic_quotes_gpc')) {
	stripVar($_GET);
	stripVar($_POST);
	stripVar($_COOKIE);
	stripVar($_REQUEST);
}

$dbh = pg_connect($conf['db_connection_string']);

if ($dbh === false)
	die ("can't connect to the database\n");

?>
