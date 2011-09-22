#!/usr/bin/perl

$VERSION = q/Revision: 1/;

%IRSSI = (
  authors       => q!Benjamin P. Burhans (bburhans)!,
  name          => q!do!,
  description   => q!Provides /do, an intelligent op-yourself-and-do-something-useful command!,
  license       => q!GPLv2!,
  changed       => q!2011-08-18 03:03:50Z!,
);

use strict;
use warnings;

use Irssi;
use Irssi::Irc;

use constant TIMEOUT => 10; ## how long we should wait for ops before abandoning the request. Adjust as appropriate. TODO: make this a setting

my %pending = (
  timeout_tag => "", ## this is used for holding open a pending request
  time => 0, ## timestamp (undef for no pending request)
  channel => { ## everything needed to uniquely identify the origin window item
    name => "", ## witem->{name}
    tag => "", ## witem->{server}
  },
  nick => "", ## the current user's nick object in the origin channel
  commands => [], ## a queue of strings to be executed when we have chanop
);

my %template = %pending; ## the state feature's behavior on non-scalars is "forbidden" so this'll have to suffice.

sub extinguish
{
  ## clean up after successfully executing or timing out on a command
  %pending = %template;
  $pending{commands} = []; ## recreate the empty array
  Irssi::signal_remove('nick mode changed','fire');
}

sub compare
{
  ## This method is a bit of a misnomer, since it's also doing some validation.
  my $witem = shift;
  return (
    $pending{channel}{name} and
    $pending{channel}{tag} and
    $pending{channel}{name} eq $witem->{name} and
    $pending{channel}{tag} eq $witem->{server}->{tag} and
    1
  );
}

sub fire
{
  my($c,$n)=@_;
  if(($c->{server}->{nick} eq $n->{nick})&&($n->{op})&&(time<=$pending{time})&&(compare($c)))
  {
    foreach(@{$pending{commands}})
    {
      $c->command($_);
    }
    Irssi::timeout_remove($pending{timeout_tag});
    extinguish();
  }
}

sub cmd_do
{
  my ($d, undef, $c) = @_;
  if (defined($c) && ($c->{type} eq "CHANNEL"))
  {
    if ($c->{chanop})
    {
      $c->command($d);
    }
    else
    {
      if ($pending{time})
      {
        if(compare($c))
        {
          push(@{$pending{commands}}, $d);
        }
        else
        {
          $c->command("echo We already have a pending op request on another channel, so we can't $d"); ## TODO: implement safe queuing across channels
        }
      }
      else
      {
        $pending{channel}{name} = $c->{name};
        $pending{channel}{tag} = $c->{server}->{tag};
        push(@{$pending{commands}}, $d);
        $pending{time}=time+10;
        $pending{timeout_tag} = Irssi::timeout_add_once(TIMEOUT * 1000, 'extinguish', undef);
        Irssi::signal_add_last('nick mode changed','fire');
        $c->command("cs op ".$c->{name});
      }
    }
  }
  else
  {
    Irssi::print("You're not in a channel!");
  }
}

Irssi::command_bind('do', 'cmd_do');

# vim:set shiftwidth=2 softtabstop=2 expandtab tabstop=2:
