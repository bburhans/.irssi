#!/usr/bin/perl

use strict;
use Irssi;
use Irssi::Irc;
use vars qw($VERSION %IRSSI);

$VERSION = "1.0";
%IRSSI = (
    authors     => 'Nathan Handler',
    contact     => 'nhandler@ubuntu.com',
    name        => 'bansearch',
    description => 'Searches for bans, quiets, and channel modes affecting a user',
    license     => 'GPLv3+',
);

my($channel,$person,$nick,$user,$host,$real,$account,$string,$issues);

sub bansearch {
	my($data,$server,$witem) = @_;

	&reset();

	($person,$channel)=split(/ /, $data, 2);
	if($channel!~m/^#/ && $person!~m/^\s*$/ && $witem->{type} eq "CHANNEL") {
		$channel=$witem->{name};
	}
	if($channel!~m/^#/ || $person=~m/^\s*$/) {
		Irssi::active_win()->print("\x02Usage\x02: /bansearch nick [#channel]");
		return;
	}

	Irssi::active_win()->print("\x02Channel\x02: $channel");

	$server->redirect_event('whois',0, $person, 1, undef,
	{
	  'event 311' => 'redir rpl_whoisuser',
	  'event 318' => 'redir rpl_endofwhois',
	  'event 330' => 'redir rpl_whoisloggedin',
	  'event 402' => 'redir err_nosuchserver',
	  '' => 'event empty',
	}
	);
	$server->send_raw("WHOIS $person $person");
}	
#Irssi::signal_add('event empty', 'EMPTY');
Irssi::signal_add('redir rpl_whoisuser', 'RPL_WHOISUSER');
Irssi::signal_add('redir rpl_endofwhois', 'RPL_ENDOFWHOIS');
Irssi::signal_add('redir err_nosuchserver', 'ERR_NOSUCHSERVER');
Irssi::signal_add('redir err_nosuchchannel', 'ERR_NOSUCHCHANNEL');
Irssi::signal_add('redir rpl_whoisloggedin', 'RPL_WHOISLOGGEDIN');
Irssi::signal_add('redir rpl_banlist', sub { my($server,$data) = @_; RPL_BANLIST($server, "Ban $data"); });
Irssi::signal_add('redir rpl_endofbanlist', sub { my($server,$data) = @_; RPL_ENDOFBANLIST($server, "Ban $data"); });
Irssi::signal_add('redir rpl_quietlist', sub { my($server,$data) = @_; RPL_BANLIST($server, "Quiet $data"); });
Irssi::signal_add('redir rpl_endofquietlist', sub { my($server,$data) = @_; RPL_ENDOFBANLIST($server, "Quiet $data"); });
Irssi::signal_add('redir rpl_channelmodeis', 'RPL_CHANNELMODEIS');

sub EMPTY {
	my($server, $data) = @_;

	Irssi::print("\x02EMPTY\x02: $data");
}

sub RPL_BANLIST {
	my($server, $data) = @_;
	my($type, undef, undef, $mask, undef, undef) = split(/ /, $data, 6);
	my $maskreg = $mask;
	$maskreg=~s/\$\#.*$//;	#Support matching ban-forwards
	$maskreg=~s/\./\\./g;
	$maskreg=~s/\//\\\//g;
	$maskreg=~s/\@/\\@/g;
	$maskreg=~s/\[/\\[/g;
	$maskreg=~s/\]/\\]/g;
	$maskreg=~s/\|/\\|/g;
	$maskreg=~s/\?/\./g;
	$maskreg=~s/\*/\.\*\?/g;

	if($maskreg=~m/^\$/) {	#extban
		if($maskreg=~m/^\$a:(.*?)$/i) {
			if($account=~m/$1/i) {
				Irssi::active_win()->print("$type against \x02$mask\x02 matches $account");
				$issues++;
			}
			else {
#				Irssi::active_win()->print("$type against \x02$mask\x02 does NOT match $account");
			}
		}
		if($maskreg=~m/^\$~a$/i) {
			if($account=~m/^\s*$/) {
				Irssi::active_win()->print("$type against \x02$mask\x02 matches unidentified user.");
				$issues++;
			}
			else {
#				Irssi::active_win()->print("$type against \x02$mask\x02 does NOT match $account");
			}
		}
		if($maskreg=~m/^\$r:(.*?)$/i) {
			if($real=~m/$1/i) {
				Irssi::active_win()->print("$type against \x02$mask\x02 matches real name of $real");
				$issues++;
			}
			else {
#				Irssi::active_win()->print("$type against \x02$mask\x02 does NOT match real name of $real");
			}
		}
		if($maskreg=~m/^\$x:(.*?)$/i) {
			my $full = "$nick!user\@host\#$real";
			if($full=~m/$1/i) {
				Irssi::active_win()->print("$type against \x02$mask\x02 matches $full");
				$issues++;
			}
			else {
#				Irssi::active_win()->print("$type against \x02$mask\x02 does NOT match $full");
			}
		}
	}
	else {	#Normal Ban
		if($string=~m/$maskreg/i) {
			Irssi::active_win()->print("$type against \x02$mask\x02 matches $string");
			$issues++;
		}
		else {
	#		Irssi::active_win()->print("$type against \x02$mask\x02 does NOT match $string");
		}
	}
}

sub RPL_ENDOFBANLIST {
	my($server, $data) = @_;
#	Irssi::active_win()->print("End of Ban List");
	if($data=~m/^Ban/) {
		$server->redirect_event('mode b',0, $channel, 0, undef,
		{
		  'event 367' => 'redir rpl_quietlist',
		  'event 368' => 'redir rpl_endofquietlist',
		  '' => 'event empty',
		}
		);
		$server->send_raw("MODE $channel q");
	}
	elsif($data=~m/^Quiet/) {
		$server->redirect_event('mode channel',0, $channel, 0, undef,
		{
		  'event 324' => 'redir rpl_channelmodeis',
		  '' => 'event empty',
		}
		);
		$server->send_raw("MODE $channel");
	}
}

sub RPL_WHOISUSER {
	my($server, $data) = @_;
	(undef, $nick, $user, $host, undef, $real) = split(/ /, $data, 6);
	$real=~s/^://;
	Irssi::active_win()->print("\x02User\x02: $nick!$user\@$host $real");
}

sub RPL_ENDOFWHOIS {
	my($server, $data) = @_;
#	Irssi::active_win()->print("End of Whois");
	$string="$nick!$user\@$host";
	$server->redirect_event('mode b',0, $channel, 0, undef, 
	{
	  'event 367' => 'redir rpl_banlist',
	  'event 368' => 'redir rpl_endofbanlist',
	  'event 403' => 'redir err_nosuchchannel',
	  '' => 'event empty',
	}
	);
	$server->send_raw("MODE $channel b");
}

sub RPL_WHOISLOGGEDIN {
	my($server, $data) = @_;

	(undef, undef, $account, undef) = split(/ /, $data, 4);

	Irssi::active_win()->print("\x02Account\x02: $account");
}

sub ERR_NOSUCHSERVER {
	my($server, $data) = @_;

	Irssi::active_win()->print("$person is currently offline.");
}

sub ERR_NOSUCHCHANNEL {
	my($server, $data) = @_;

	Irssi::active_win()->print("$channel does not exist.");
}

sub RPL_CHANNELMODEIS {
	my($server, $data) = @_;
	my(undef, undef, $modes, $args) = split(/ /, $data, 4);
	Irssi::active_win()->print("\x02Channel Modes\x02: $modes");
	if($modes=~m/i/) {
		Irssi::active_win()->print("Channel is \x02invite-only\x02 (+i)");
		$issues++;
	}
	if($modes=~m/k/) {
		Irssi::active_win()->print("Channel has a \x02password\x02 (+k)");
		$issues++;
	}
	if($modes=~m/r/) {
		if($account=~m/^\s*$/) {
			Irssi::active_win()->print("Channel is \x02blocking unidentified users\x02 (+r) and user is not identified");
			$issues++;
		}
	}
	if($modes=~m/m/) {
		my $n = $server->channel_find("$channel")->nick_find("$nick");
		if($n->{voice} == 0 && $n->{op} == 0) {
			Irssi::active_win()->print("Channel is \x02moderated\x02 (+m) and user is not voiced or oped");
			$issues++;
		}
	}

	if($issues == 0) {
		Irssi::active_win()->print("There does not appear to be anything preventing $person from joining/talking in $channel");
	}
	else {
		Irssi::active_win()->print("There are \x02$issues issues\x02 that might be preventing $person from joining/talking in $channel");
	}
}

sub reset {
        $channel='';
        $person='';
        $nick='';
        $user='';
        $host='';
        $real='';
        $account='';
        $string='';
	$issues=0;

	&register_redirects();
}	

sub register_redirects {
	#whois
	Irssi::Irc::Server::redirect_register('whois', 1, 0,
	{ "event 311" => 1 },
	{
	  "event 401" => 1,   #No Such Nick
	  "event 318" => 1,   #End of WHOIS
	  "event 402" => 1,   #No such server
	},
	{ "event 318" => 1 }   #After 401, we should get 318, but in OPN we don't..
	);

	#mode b
	Irssi::Irc::Server::redirect_register('mode b', 0, 0,
  	{ "event 367" => 1 }, # start events
	{ 					  # stop events
	  "event 368" => 1,   # End of channel ban list
	  "event 403" => 1,   # no such channel
	  "event 442" => 1,   # "you're not on that channel"
	  "event 479" => 1    # "Cannot join channel (illegal name)"
	},
	undef, 				  # optional events
	);

	#mode channel
	Irssi::Irc::Server::redirect_register('mode channel', 0, 0, undef,
	{ # stop events
	  "event 324" => 1, # MODE-reply
	  "event 403" => 1, # no such channel
	  "event 442" => 1, # "you're not on that channel"
	  "event 479" => 1  # "Cannot join channel (illegal name)"
	},
	{ "event 329" => 1 } # Channel create time
	);
}

Irssi::command_bind('bansearch', 'bansearch');
