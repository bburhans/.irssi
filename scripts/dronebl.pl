###################################################################
# DroneBL RPC2 query for irssi
# This script allows querying the DroneBL using RPC2 calls, which
# will allow queries including wildcards and ranges.  Examples:
# /dronebl 127.0.0.?
# /dronebl 10.0.*
# /dronebl 192.168.[1-20].*
#
# It also allows addition of ip addresses via "add $type $ipaddr": 
# /dronebl add 1 10.10.2.20 
#
# To see a list of types, issue:
# /dronebl types
#
# For more information:
# /dronebl help
#
# Requires LWP (libwww-perl -- which you probably already have),
# and Text::TabularDisplay (available via CPAN or your vendor).
# 
# You pretty much have to install LWP via cpan(1) or your vendor's
# package distribution system (such as apt-get(1)), but you can 
# download Text::TabularDisplay, untar, and mkdir 
# ~/.irssi/scripts/Text; cp TabularDisplay.pm ~/.irssi/scripts/Text
#
# This program is free software. It comes without any warranty, to
# the extent permitted by applicable law. You can redistribute it
# and/or modify it under the terms of the Do What The Fuck You Want
# To Public License, Version 2, as published by Sam Hocevar. See
# http://sam.zoy.org/wtfpl/COPYING for more details.
###################################################################

use vars qw($VERSION %IRSSI);
use strict;
use Irssi qw(command_bind settings_get_str settings_add_str settings_get_bool settings_add_bool);
use LWP::UserAgent;
use HTTP::Request::Common;
use Text::ParseWords 'shellwords';
use Text::TabularDisplay;

$VERSION = '0.5';
%IRSSI = (
	authors		=> 'Steve Church (rojo), Jmax',
	contact		=> 'irc.atheme.org on #dronebl',
	name		=> 'DroneBL RPC2 query / host submission',
	description	=> 'query (and modify) the DroneBL with wildcards via irssi',
	license		=> 'WTFPLv2',
	url		=> 'http://headcandy.org/rojo/',
	changed		=> $VERSION,
	modules		=> 'LWP::UserAgent HTTP::Request Text::TabularDisplay',
	commands	=> 'dronebl'
);

settings_add_str('DroneBL', 'dronebl_rpckey', '');
settings_add_str('DroneBL', 'dronebl_columns', 'listed ip type timestamp');
settings_add_bool('DroneBL', 'dronebl_show_only_active', 0);
settings_add_bool('DroneBL', 'dronebl_show_type_names', 0);

my $DroneBL = "http://dronebl.org/RPC2";
my $classes_page = "http://dronebl.org/classes?format=txt";
my $expired_after = 86400*90; # 90 days

my $userAgent = LWP::UserAgent->new(agent => 'perl post');
my %classes;

if (!settings_get_str('dronebl_rpckey')) {
	dronebl_nag(0);
}

command_bind dronebl => \&dronebl;

sub dronebl {
	my ($data, $server, $channel) = @_;

	my @args = shellwords($data);
	if ($args[0] eq 'help') {
		dronebl_help($channel);
		return;
	} elsif ($args[0] eq 'types') {
		dronebl_update_classes($channel);
		dronebl_print('Types: ');
		my @types = sort { $a <=> $b } keys %classes;
		foreach my $type (@types) {
			dronebl_print( sprintf('%3s', $type) . ': ' . $classes{$type} );
		}
		return;
	} elsif ($args[0] eq 'add' || $args[0] eq 'submit') {
		my ($type, $ipaddr) = @args[1..2];
		if (!$type or $ipaddr !~ /^[0-9\.]+$/) {
			dronebl_print('Need type and IP address');
			return;
		}
		my ($matches, $active, $expired) = dronebl_lookup($ipaddr);
		if ($matches && $active && !$expired) {
			dronebl_print("$ipaddr: Already listed");
		} else {
			my ($line) = dronebl_request($channel, "<add ip='$ipaddr' type='$type' />" );
			dronebl_print("$ipaddr: Success adding") if $line;
		}
	} elsif ($args[0] && $args[0] =~ /[0-9\.\?\*\%_\[\]-]+/) {
		my @clean;
		foreach (@args) { push @clean, $_ if /^[0-9\.\?\*\%_\[\]-]+$/; }
		my ($matches, $active, $expired, @results) = dronebl_lookup($channel, @clean);
		my @columns = split(/\s+/, settings_get_str('dronebl_columns'));
		my $table = Text::TabularDisplay->new(@columns);
		if ($matches) {
			foreach my $result (@results) {
				if ($result->{listed} || !settings_get_bool('dronebl_show_only_active')) {
					$result->{listed} = ($result->{listed}) ? 'yes' : 'no';
					$result->{listed} .= ' (exp)' if $result->{expired};
					$result->{timestamp} = scalar gmtime($result->{timestamp});
					if (settings_get_bool('dronebl_show_type_names')) {
						my $type_name = dronebl_class($channel, $result->{type});
						$result->{type} .= " ($type_name)" if $type_name;
					}
					my @row;
					foreach my $column (@columns) {
						push @row, $result->{$column};
					}
					$table->add(@row);
				}
			}
			my @table = split /\n/, $table->render;
			dronebl_print("%8%#" . $_ . "%#%8", $channel) foreach @table;
			dronebl_print("%W%Nquery: $data | matches: $matches | active: $active | expired: $expired", $channel);
		} else {
			dronebl_print("%W%Nquery: $data | no match(es)");
		}

	} else {
		dronebl_help($channel);
	}
}

sub dronebl_lookup {
	my ($channel, @queries) = @_;
	$_ = "<lookup ip='$_' />" foreach @queries;
	my @lines = dronebl_request($channel, @queries) or return;
	my ($matches, $active, $expired) = (0, 0, 0);
	my @results;
	foreach my $line (@lines) {
		if ($line =~ /<result/) {
			++$matches;
			my @params = split(/\s/, $line);
			my %keys;
			foreach my $item (@params) {
				if (grep(/=/, $item)) {
					$item =~ s/"//g;
					my @temp = split(/=/, $item);
					$keys{$temp[0]} = $temp[1];
				}
			}
			++$active if $keys{listed};
			if ($keys{timestamp} <= (time - $expired_after)) { ++$expired; $keys{expired}++; }
			push @results, \%keys;
		}
	}
	return $matches, $active, $expired, @results;
}

sub dronebl_request {
	my ($channel, @reqs) = @_;
	my $rpcKey = settings_get_str('dronebl_rpckey');
	if (!$rpcKey) {
		dronebl_nag($channel);
		return;
	}
	my $message = "<?xml version=\"1.0\"?>\n<request key='$rpcKey'>\n";
	$message .= "\t$_\n" foreach @reqs;
	$message .= "</request>\n";
	my $response = $userAgent->request(POST $DroneBL, Content_Type => 'text/xml', Content => $message);
	if ($response->is_success) {
		my $xml = $response->as_string;
		my @lines = split(/\n/, $xml);
		if ($xml =~ /error/) {
			my ($error, $error_message, $error_query);
			foreach my $line (@lines) {
				if ($line =~ /<code>/) { $error = $line; }
				if ($line =~ /<message>/) { $error_message = $line; }
				if ($line =~ /<data>/) { $error_query = $line; }
			}
			s{\s*</?[^>]+>}{}g for ($error, $error_message, $error_query);
			$error_query =~ s/%/%%/g;
			dronebl_print("The server returned an error message ($error: $error_message)", $channel);
			dronebl_print("Extended information: $error_query", $channel) if $error_query; 
			return;
		}
		return @lines;
	}
	else {
		dronebl_print($response->error_as_HTML, $channel);
		return;
	}
}

sub dronebl_print {
	my ($data, $channel) = @_;
	if ($channel && $channel->{type} eq "CHANNEL") {
		$channel->print($data, MSGLEVEL_CLIENTCRAP);
	}
	else {
		print CLIENTCRAP $data;
	}

}

sub dronebl_help {
	my ($channel) = @_;
	dronebl_print(<<EOHELP, $channel);
%W%8DroneBL RPC2 query for irssi%8 %N
%W%NThis script allows querying the DroneBL using RPC2 calls, which
%W%Nwill allow queries including wildcards and ranges.  Examples:
%W/dronebl 127.0.0.?%N
%W/dronebl 10.0.*%N
%W/dronebl 192.168.[1-20].*%N

%W%NIt also allows addition of ip addresses via "add \$type \$ipaddr": 
%W/dronebl add 1 10.10.2.20 

%W%NTo see a list of types, issue:
%W/dronebl types

%W%NRequires an RPCKey.  Set the key by typing the following:
%W/set dronebl_rpckey XXXXXXXXXXXXXXXXXXXXXXXXXXX%N
%W%Nreplacing the X's with your key, of course.  If you are a network
%W%Nsecurity professional and you do not have an RPCKey, one can be
%W%Nrequested from %chttp://dronebl.org/rpckey_signup%n

%W%NYou can change the format of the output by setting the 
%Wdronebl_columns%N variable.  Valid columns are as follows:
%W        ip id type comment listed timestamp%N
%W%NAdd / remove / rearrange columns as you see fit.  Example:
%W/set dronebl_columns listed ip type timestamp%N

%W%NIf you have the screen real-estate, you can expand the \"type\"
%W%Ncolumn numbers into their canonical names by setting the
%Wdronebl_show_type_names%N variable to %WON%N.

%W%NFinally, you can ignore inactive entries by setting the
%Wdronebl_show_only_active%N variable to %WON%N.
EOHELP
}

sub dronebl_nag {
	my ($channel) = @_;
	my $nag_message = "
Please store an RPCKey.  You will be unable to make queries until
you have done so.  Set the key by typing the following:

%W/set dronebl_rpckey XXXXXXXXXXXXXXXXXXXXXXXXXXX%N

replacing the X's with your key, of course.  If you are a network
security professional and you do not have an RPCKey, one can be
requested from %W%N%chttp://dronebl.org/rpckey_signup%n

For more options, see %W/dronebl help%N
";
	dronebl_print($nag_message, $channel);
}

sub dronebl_class {
	my ($channel, $category) = @_;
	my $default = dronebl_update_classes($channel);
	my $default &&= "Not yet implemented";
	if (defined $classes{$category}) {
		return $classes{$category};
	}
	else {
		return $default;
	}
}

sub dronebl_update_classes {
	my $channel = shift;
	if (keys(%classes) < 1) {
		dronebl_print("Fetching up-to-date category descriptions...", $channel);
		my $response = $userAgent->request(GET $classes_page);
		if ($response->is_success) {
			foreach my $line (split(/\n/, $response->as_string)) {
				if (grep(/\t/, $line)) {
					my @parms = split(/\t/, $line);
					$classes{@parms[0]} = @parms[1];
				}
			}
		}
		else { return; }
	}
	return 1;
}
