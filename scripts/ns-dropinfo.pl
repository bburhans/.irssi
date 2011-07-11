#!/usr/bin/perl
use strict;
use vars qw($VERSION %IRSSI);
 
use Date::Calc qw(Decode_Month Today Delta_Days Delta_YMDHMS);
 
use Irssi;
$VERSION = '1.00';
%IRSSI = (
	authors		=>	'Nathan Handler',
	contact		=>	'nhandler@ubuntu.com',
	name		=>	'maskSearch',
	description	=>	'Adds drop eligibility info to NickServ responses. Based on script by Mike Quin.',
	license		=>	'GPLv3+',
);
 
my($expire, $rMonth, $rDay, $rHour, $rMinute, $rSecond, $rYear);
 
&reset();
 
sub reset {
	$expire = 70;	#Considers a nick droppable after 70 days (10 weeks) + 1 week per year registered
}
 
sub event_notice {
	my($server, $message, $sender, $sender_host, $recipient) = @_;
	my $notice_format = '{notice $0{pvtnotice_host $1}}$2';
 
	if($sender =~ m/^NickServ$/i) {
		if($message =~ m/^Registered : (\w{3}) (\d{2}) (\d{2}):(\d{2}):(\d{2}) (\d{4}) \(.*?\)$/) {
                        $rMonth = $1;
                        $rDay = $2;
                        $rHour = $3;
                        $rMinute = $4;
                        $rSecond = $5;
                        $rYear = $6;
			$expire += int(Delta_Days($rYear, Decode_Month($rMonth), $rDay, Today())/365)*7;
		}
		elsif($message =~ m/^Last seen  : (.*)$/) {
			my $when = $1;
			my $ddays;
			if($when =~ m/^now$/) {
				$ddays = 0;
			}
			elsif($when =~ m/^\(about (\d+) weeks ago\)$/) {
				$ddays = 7*$1;
			}
			elsif($when =~ m/^(\w{3}) (\d{2}) (\d{2}):(\d{2}):(\d{2}) (\d{4}) \(.*?\)$/) {
				$ddays = Delta_Days($6, Decode_Month($1), $2, Today());
                                if(Delta_Days($rYear, Decode_Month($rMonth), $rDay, Today()) >= 14) {
                                    my($dY, $dM, $dD, $dHH, $dMM, $dSS) = Delta_YMDHMS($rYear, Decode_Month($rMonth), $rDay, $rHour, $rMinute, $rSecond,
                                                                                       $6, Decode_Month($1), $2, $3, $4, $5);
                                    if($dY==0 && $dM==0 && $dD==0 && $dHH<2) {
                                        $ddays = 999999;    #If the nick is at least 2 weeks old and last seen less than 2 hours after registering,
                                    }                       #Set $ddays to a VERY large number to ensure the nick gets marked as Droppable.
                                }
			}
                        
			if($ddays >= $expire) {
				$notice_format .= " (Droppable)";
			}
			else {
				my $remaining = $expire-$ddays;
				$notice_format .= " (NOT Droppable for $remaining days)";
			}
			&reset();
		}
	}
	$server->command("^format notice_private $notice_format");
}
 
Irssi::signal_add('message irc notice', 'event_notice');
