#!/usr/bin/perl -w
# This converts a dump of a yang database's public schema

# It's quite simple: we don't want the counters_detail* tables…
my $in_detail=0;
foreach (<>)
{
	s/--.*//; # Remove comments
	next if (/^$/); # Skip empty lines
	if (/^CREATE TABLE counters_detail_\d+/)
	{
		$in_detail=1;
	}
	print unless ($in_detail or /counters_detail_\d+/);
	if (/^\);$/)
	{
		$in_detail=0;
	}
}
