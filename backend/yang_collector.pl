#!/usr/bin/perl -w

=head1 About

Auteur : marc.cousin@dalibo.com

Version 1.0 : 2010-08-04

Name : process_perfdata.pl

=head1 SYNOPSIS

process_perfdata.pl [--daemon] [--verbose] --directory=data_dir [--frequency=scrutinizing_frequency] --config=configuration_file

=head1 Use

This program scrutinizes nagios' perfdata directory.
Spooled files have to be of this format (in the nagios configuration) :

host_perfdata_file_template=DATATYPE::HOSTPERFDATA\tTIMET::$TIMET$\tHOSTNAME::$HOSTNAME$\tHOSTPERFDATA::$HOSTPERFDATA$\tHOSTCHECKCOMMAND::$HOSTCHECKCOMMAND$\tHOSTSTATE::$HOSTSTATE$\tHOSTSTATETYPE::$HOSTSTATETYPE$\tHOSTOUTPUT::$HOSTOUTPUT$
service_perfdata_file_template=DATATYPE::SERVICEPERFDATA\tTIMET::$TIMET$\tHOSTNAME::$HOSTNAME$\tSERVICEDESC::$SERVICEDESC$\tSERVICEPERFDATA::$SERVICEPERFDATA$\tSERVICECHECKCOMMAND::$SERVICECHECKCOMMAND$\tHOSTSTATE::$HOSTSTATE$\tHOSTSTATETYPE::$HOSTSTATETYPE$\tSERVICESTATE::$SERVICESTATE$\tSERVICESTATETYPE::$SERVICESTATETYPE$\tSERVICEOUTPUT::$SERVICEOUTPUT$

=cut

use strict;

use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use POSIX qw(setsid);
use DBI;

my $verbose=0;

# These are globals. No point in sending them from function to function
my $connection_string;
my $user;
my $password;


# The next two functions were stolen from Nagios::Plugin::Performance
# They do the parsing of the PERFDATA string

my $value = qr/[-+]?[\d\.,]+/;
my $value_re = qr/$value(?:e$value)?/;
my $value_with_negative_infinity = qr/$value_re|~/;

sub parse_perfrecord {
	my $string = shift;
	$string =~ /^'?([^'=]+)'?=($value_re)([\w%]*);?($value_with_negative_infinity\:?$value_re?)?;?($value_with_negative_infinity\:?$value_re?)?;?($value_re)?;?($value_re)?/o;
	return undef unless ((defined $1 && $1 ne "") && (defined $2 && $2 ne ""));
	my @info = ($1, $2, $3, $4, $5, $6, $7);
	# We convert any commas to periods, in the value fields
	map { defined $info[$_] && $info[$_] =~ s/,/./go } (1, 3, 4, 5, 6);

	# Check that $info[1] is an actual value
	# We do this by returning undef if a warning appears
	my $performance_value;
	{
		my $not_value;
		local $SIG{__WARN__} = sub { $not_value++ };
		$performance_value = $info[1]+0;
		return undef if $not_value;
	}
    my $p = {
        label => $info[0], value => $performance_value, uom => $info[2], warning => $info[3], critical => $info[4], 
        min => $info[5], max => $info[6]} ;
	return $p;
}


sub parse_perfstring {
	my ($perfstring) = @_;
	my @perfs = ();
	my $p;
	while ($perfstring) {
		$perfstring =~ s/^\s*//;
		# If there is more than 1 equals sign, split it out and parse individually
		if (@{[$perfstring =~ /=/g]} > 1) {
			$perfstring =~ s/^(.*?=.*?)\s//;
			if (defined $1) {
				$p = parse_perfrecord($1);
			} else {
				# This could occur if perfdata was soemthing=value=
				# Since this is invalid, we reset the string and continue
				$perfstring = "";
				$p = parse_perfrecord($perfstring);
			}
		} else {
			$p = parse_perfrecord($perfstring);
			$perfstring = "";
		}
		push @perfs, $p if $p;
	}
	return \@perfs;
}


# This function splits a line of performance data and parses it.
# Parsing of the perfdata part is done by parse_perfstring

sub parse_perfline {
	my ($line)=@_;
	my %parsed;
	# Performance lines are made of KEY::VALUE\tKEY::VALUE...
	my @elements=split("\t",$line);
	(@elements > 0) or die "Can't understand this line : <$line>\n";
	foreach my $element (@elements)
	{
		# This has to be a key-value. Else I die !
		$element =~ /^(\S+)::(.*)$/ or die "Can't understand this attribute : <$element>\n";
		$parsed{$1}=$2;
	}
	# Ok. Is it a serviceperfdata or a hostperfdata ?
	# we consider a hostperfdata a serviceperfdata of a certain kind: as a service desc, it will be host
	if ($parsed{DATATYPE} eq 'HOSTPERFDATA')
	{
		$parsed{SERVICEDESC}='HOST';
		$parsed{SERVICEPERFDATA}=$parsed{HOSTPERFDATA};
		$parsed{SERVICEOUTPUT}=$parsed{HOSTOUTPUT};
		undef $parsed{HOSTPERFDATA};
		undef $parsed{HOSTOUTPUT};
	}
	# Now everything is the same kind of performance data
	# Let's split the perfdata
	my $perfsref=parse_perfstring($parsed{SERVICEPERFDATA});
	# We store in the same hash the parsed version of the performance data
	# With a reference to @perfs. This way we have a complete parsed structure of the file
	$parsed{SERVICEPERFDATA_PARSED}=$perfsref;
	return \%parsed;
}

# Simple function to convert MB to B, Kib to b, returning the base unit and multiplying factor
sub eval_uom
{
	my ($uom)=@_;
	return ('',1) unless $uom; # No uom
	my $multfactor;
	my $basic_uom;
	# Okay, is it starting with ki, Mi, Gi, Ti, k, M, G, T ?
	# Repetitive but simple code
	if ($uom =~ /^ki(.*)/)
	{
		$multfactor=1000;
		$basic_uom=$1;
	}
	elsif ($uom =~ /^k(.*)/)
	{
		$multfactor=1024;
		$basic_uom=$1;
	}
	elsif ($uom =~ /^Mi(.*)/)
	{
		$multfactor=1000*1000;
		$basic_uom=$1;
	}
	elsif ($uom =~ /^M(.*)/)
	{
		$multfactor=1024*1024;
		$basic_uom=$1;
	}
	elsif ($uom =~ /^Gi(.*)/)
	{
		$multfactor=1000*1000*1000;
		$basic_uom=$1;
	}
	elsif ($uom =~ /^G(.*)/)
	{
		$multfactor=1024*1024*1024;
		$basic_uom=$1;
	}
	elsif ($uom =~ /^Ti(.*)/)
	{
		$multfactor=1000*1000*1000*1000;
		$basic_uom=$1;
	}
	elsif ($uom =~ /^T(.*)/)
	{
		$multfactor=1024*1024*1024*1024;
		$basic_uom=$1;
	}
	else
	{
		# I don't understand this unit. Let's keep it as is
		$multfactor=1;
		$basic_uom=$uom;
	}
	return ($basic_uom,$multfactor);
}


# This function reads a file line by line and calls parse_perfline for each one
# It then returns an array with an element per counter
sub read_file
{
	my ($filename)=@_;
	my $fh;
	my @parsed_file;
	open ($fh,$filename) or die "Can't open $filename : $!\n";
	while (my $line=<$fh>)
	{
		my $parsed_line=parse_perfline($line);

		# We want to return an array of perfcounters (hash). We are interested in
		# TIMET, HOSTNAME, SERVICEDESC, 
		# every label and value element of SERVICEPERFDATA_PARSED
		# So we push that into @parsed_file
		foreach my $perfcounterref (@{$parsed_line->{SERVICEPERFDATA_PARSED}})
		{
			my %perfcounter;
			$perfcounter{TIMET}=$parsed_line->{TIMET};
			$perfcounter{HOSTNAME}=$parsed_line->{HOSTNAME};
			$perfcounter{SERVICEDESC}=$parsed_line->{SERVICEDESC};
			$perfcounter{LABEL}=$perfcounterref->{label};
			# Okay, lets work on the units. We normalize everything
			my ($basic_uom,$multfactor)=eval_uom($perfcounterref->{uom});
			$perfcounter{VALUE}=$perfcounterref->{value}*$multfactor;
			$perfcounter{UOM}=$basic_uom;
			if ($verbose)
			{
				$perfcounter{ORIG_UOM}=$perfcounterref->{uom};
				$perfcounter{ORIG_VALUE}=$perfcounterref->{value};
				$perfcounter{MULTFACTOR}=$multfactor;
			}

			

			# Done. We push it into our array of results
			push @parsed_file,\%perfcounter;
		}
	}
	$verbose and print Dumper(\@parsed_file);
	return \@parsed_file;
}

# Daemonize function : fork, kill the father, detach from console, go to root
sub daemonize
{
        my $child=fork();
        if ($child){
                # I'm the father
                #
                exit 0;
        }
        close(STDIN);
        close(STDOUT);
        close(STDERR);
        open STDOUT,">/dev/null";
        open STDERR,">/dev/null";
	POSIX::setsid();
	chdir '/';
}



# Database access functions

# This function connects to the database and returns a db handle
sub dbconnect
{
	my $dbh=DBI->connect($connection_string,$user,$password)
		or die "Can't connect to " . $connection_string . "\n";
	return $dbh;
}

# This function inserts parsed data into the database
sub insert_parsed_data
{
	my ($dbh,$parsed_data,$filename)=@_;
	my $sth=$dbh->prepare_cached('SELECT insert_record(?,?,?,?,?,?)');
	foreach my $counter (@{$parsed_data})
	{
		$sth->execute($counter->{HOSTNAME},
		              $counter->{TIMET},
		              $counter->{SERVICEDESC},
		              $counter->{LABEL},
		              $counter->{VALUE},
			      $counter->{UOM}) 
			or die "Can't execute: $counter->{HOSTNAME},$counter->{TIMET},$counter->{SERVICEDESC},$counter->{LABEL},$counter->{VALUE},$counter->{UOM}.\nFile : $filename \n";
		my $result=$sth->fetchrow();
		($result) or die "Failed inserting: <$result> $counter->{HOSTNAME},$counter->{TIMET},$counter->{SERVICEDESC},$counter->{LABEL},$counter->{VALUE},$counter->{UOM}\n";
		$sth->finish();
	}
}

# Watch the incoming directory
# As soon as a file is there, send it to read_file.
sub watch_directory
{
	my ($dirname,$frequency)=@_;
	while(1)
	{
		my $dir;
		opendir($dir,$dirname) or die "Can't open directory $dirname: $!\n";
		while (my $entry=readdir $dir)
		{
			next if ($entry eq '.' or $entry eq '..');
			my $parsed=read_file("$dirname/$entry");
			my $dbh=dbconnect();# We reconnect for each file, to be sure there is no memory leak
			$dbh->begin_work();
			insert_parsed_data($dbh,$parsed,"$dirname/$entry");
			unlink("$dirname/$entry") or die "Can't remove $dirname/$entry: $!\n";
			$dbh->commit();
		}
		sleep $frequency;
	}
}

# This function parses the configuration file and modifies variables
# It is hand made and very dumb, due to the simple configuration file
sub parse_config
{
	my ($config,$refdaemon,$refdirectory,$reffrequency,$ref_connection_string,$ref_user,$ref_password)=@_;
	my $confH;
	open $confH,$config or die "Can't open <$config>:$!\n";
	while (my $line=<$confH>)
	{
		chomp $line;

		#It's a simple ini file
		$line =~ s/#.*//;  # Remove comments
		next if ($line eq ''); # Ignore empty lines
		$line =~ s/=\s+//; # Remove spaces after =
		$line =~ s/\s+=//; # Remove spaces before =

		$line =~ /^(.*?)=(.*)$/ or die "Can't parse <$line>\n";
		my $param=$1;
		my $value=$2;

		if ($param eq 'daemon')
		{
			$$refdaemon=$value;
		}
		elsif ($param eq 'directory')
		{
			$$refdirectory=$value;
		}
		elsif ($param eq 'frequency')
		{
			$$reffrequency=$value;
		}
		elsif ($param eq 'db_connection_string')
		{
			$$ref_connection_string=$value;
		}
		elsif ($param eq 'db_user')
		{
			$$ref_user=$value;
		}
		elsif ($param eq 'db_password')
		{
			$$ref_password=$value;
		}
		else
		{
			die "Unknown parameter <$param> in configuration file\n";
		}
	}
	close $confH;
}


# Main

# Command line options
my $daemon;
my $directory;
my $frequency;
my $help;
my $config;


my $result = GetOptions("daemon" => \$daemon,
                        "verbose" => \$verbose,
			"directory=s" => \$directory,
			"frequency=i" => \$frequency,
			"config=s" => \$config,
			"help" => \$help);

# Usage if help asked for
Pod::Usage::pod2usage(-exitval => 1, -verbose => 3) if ($help);

# Usage if no configuration file or wrong parameters
Pod::Usage::pod2usage(-exitval => 1, -verbose => 1) unless ($config and $result);


# Parse config file
parse_config($config,\$daemon,\$directory,\$frequency,\$connection_string,\$user,\$password);

# Usage if missing parameters in command line or configuration file
Pod::Usage::pod2usage(-exitval => 1, -verbose => 1) unless ($directory);


# Add default values if they are still not set up
unless ($frequency) {$frequency = 5};




daemonize if ($daemon);



# Let's work
watch_directory($directory,$frequency);


