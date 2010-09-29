<?php
function add_item($item, $url, $first = false)
{
    if ($first)
        printf('<li class="first">');
    else
        printf('<li>');
    printf('<a href="%s">%s</a></li>',
      htmlentities($url), htmlentities($item));
}

echo '<div id="bread">';
echo '<div id="adminlink"><a href="admin.php">Admin</a></div>';
echo '<ul>';
add_item('Home', 'index.php', true);
if (isset($hostname))
    add_item("Host '{$hostname}'", "services.php?hostname=$hostname");
if (isset($service))
{
    $servicelabel = "Service '{$service}'";
    if (strrpos($_SERVER['PHP_SELF'], 'service_scale.php') > 0)
    {
        $servicelabel .= ' (scale)';
        $url = "service_scale.php?hostname=$hostname&service=$service";
    }
    else if ($multi_graphs)
    {
        $servicelabel .= ' (multigraph)';
        $url = "service.php?hostname=$hostname&service=$service";
    }
    else
    {
        $url = "service.php?hostname=$hostname&service=$service&show=";
    }
    
    add_item($servicelabel, "service.php?hostname=$hostname&service=$service");
}
echo '</ul></div>';

?>
