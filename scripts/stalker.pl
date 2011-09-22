use Irssi;
use vars qw/$VERSION %IRSSI/;
use File::Spec;
use DBI;
use POSIX qw/ strftime /;

# Requires:
#   DBI
#   DBD::SQLite3

$VERSION = '0.50';
%IRSSI = (
    authors     => 'SymKat',
    contact     => 'symkat@symkat.com',
    name        => "stalker",
    decsription => 'Records and correlates nick!user@host information',
    license     => "BSD",
    url         => "http://github.com/symkat/stalker",
    changed     => "2010-10-06",
    changes     => "See Change Log",
);

# Bindings
Irssi::signal_add_last( 'event 311', \&whois_request );
Irssi::signal_add( 'message join', \&nick_joined );
Irssi::signal_add( 'nicklist changed', \&nick_changed_channel );
Irssi::signal_add( 'channel sync', \&channel_sync );

Irssi::command_bind( 'host_lookup', \&host_request );
Irssi::command_bind( 'nick_lookup', \&nick_request );

Irssi::theme_register([
    $IRSSI{'name'} => '{whois stalker %|$1}',
    $IRSSI{'name'} . '_join' => '{channick_hilight $0} {chanhost_hilight $1} has joined '
        . '{hilight $2} ({channel $3})', 
]);

# Settings
Irssi::settings_add_str( 'Stalker',  $IRSSI{name} . "_db_path", "nicks.db" );
Irssi::settings_add_str( 'Stalker',  $IRSSI{name} . "_max_recursion", 20 );
Irssi::settings_add_str( 'Stalker',  $IRSSI{name} . "_guest_nick_regex", "/^guest.*/i" );
Irssi::settings_add_str( 'Stalker',  $IRSSI{name} . "_debug_log_file", "stalker.log" );

Irssi::settings_add_bool( 'Stalker', $IRSSI{name} . "_verbose", 0 );
Irssi::settings_add_bool( 'Stalker', $IRSSI{name} . "_debug", 0 );
Irssi::settings_add_bool( 'Stalker', $IRSSI{name} . "_recursive_search", 1 );
Irssi::settings_add_bool( 'Stalker', $IRSSI{name} . "_search_this_network_only", 0 );
Irssi::settings_add_bool( 'Stalker', $IRSSI{name} . "_ignore_guest_nicks", 1 );
Irssi::settings_add_bool( 'Stalker', $IRSSI{name} . "_debug_log", 0 );
Irssi::settings_add_bool( 'Stalker', $IRSSI{name} . "_stalk_on_join", 0 );

my $count;
my %data;
my $str;

# Database

my $db = Irssi::settings_get_str($IRSSI{name} . '_db_path');
if ( ! File::Spec->file_name_is_absolute($db) ) {
    $db = File::Spec->catfile( Irssi::get_irssi_dir(), $db );
}

stat_database( $db );

my $DBH = DBI->connect(
    'dbi:SQLite:dbname='.$db, "", "",
    {
        RaiseError => 1,
        AutoCommit => 1,
    }
) or die "Failed to connect to database $db: " . $DBI::errstr;


# IRSSI Routines

sub whois_request {
    my ( $server, $data, $server_name ) = @_;
    my ( $me, $n, $u, $h ) = split(" ", $data );
   
    $server->printformat($n,MSGLEVEL_CRAP,$IRSSI{'name'},$n, 
        join( ", ", (get_records('host', $h, $server->{address}))) . "." );
}

sub host_request {
    windowPrint( join( ", ", (get_records('host', $_[0], $_[1]->{address}))) );
}

sub nick_request {
    windowPrint( join( ", ", (get_records('nick', $_[0], $_[1]->{address}))) );
}

#   Record Adding Functions
sub nick_joined {
    my ( $server, $channel, $nick, $address ) = @_;
    my ( $user, $host ) = ( split ( '@', $address, 2 ) );

    add_record( $nick, $user, $host, $server->{address}) if($host && $nick);
    
    if ( Irssi::settings_get_bool($IRSSI{name} . "_stalk_on_join") ) {
        my $window = $server->channel_find($channel);
        my @used_nicknames = get_records( 'host', $host, $server->{address} );
        
        $window->printformat( MSGLEVEL_JOINS, 'stalker_join', 
            $nick, $address, $channel, join( ", ", @used_nicknames )); 
        Irssi::signal_stop(); 
    }
}

sub nick_changed_channel {
    add_record( $_[1]->{nick}, (split( '@', $_[1]->{host} )), $_[0]->{server}->{address} ) if($_[1]->{host} =~ /@./ && $_[1]->{nick});
}

sub channel_sync {
    my ( $channel ) = @_;
    
    my $serv = $channel->{server}->{address};
    
    for my $nick ( $channel->nicks() ) {
        last if $nick->{host} eq ''; # Sometimes channel sync doesn't give us this...
#        add_record( $nick->{nick}, ( split( '@', $nick->{host} ) ), $serv ) if($nick->{host} =~ /@./ && $nick->{nick});
    } 
}


# Automatic Database Creation And Checking
sub stat_database {
    my ( $db_file ) = @_;
    my $do = 0;

    if ( ! -e $db_file  ) {
        open my $fh, '>', $db_file
            or die "Cannot create database file.  Abort.";
        close $fh;
        $do = 1;
    }
    my $DBH = DBI->connect(
        'dbi:SQLite:dbname='.$db_file, "", "",
        {
            RaiseError => 1,
            AutoCommit => 1,
        }
    );

    create_database( $db_file, $DBH ) if $do;

    my $sth = $DBH->prepare( "SELECT nick from records WHERE serv = ?" );
    $sth->execute( 'script-test-string' );
    my $sane = $sth->fetchrow_array;
    
    create_database( $db_file, $DBH ) if $sane == undef;
}

sub create_database {
    my ( $db_file, $DBH ) = @_;
    
    my $query = "CREATE TABLE records (nick TEXT NOT NULL," .
        "user TEXT NOT NULL, host TEXT NOT NULL, serv TEXT NOT NULL)";
    
    $DBH->do( "DROP TABLE IF EXISTS records" );
    $DBH->do( $query );
    my $sth = $DBH->prepare( "INSERT INTO records (nick, user, host, serv) VALUES( ?, ?, ?, ? )" );
    $sth->execute( 1, 1, 1, 'script-test-string' );
}

# Other Routines

sub add_record {
    my ( $nick, $user, $host, $serv ) = @_;
    
    # Check if we already have this record.
    my $q = "SELECT nick FROM records WHERE nick = ? AND user = ? AND host = ? AND serv = ?";
    my $sth = $DBH->prepare( $q );
    $sth->execute( $nick, $user, $host, $serv );
    my $result = $sth->fetchrow_hashref;

    if ( $result->{nick} eq $nick ) {
        debugPrint( "info", "Record for $nick skipped - already exists." );
        return 1;
    }
   
    debugPrint( "info", "Adding to DB: nick = $nick, user = $user, host = $host, serv = $serv" );

    # We don't have the record, add it.
    $sth = $DBH->prepare
        ("INSERT INTO records (nick,user,host,serv) VALUES( ?, ?, ?, ? )" );
    eval { $sth->execute( $nick, $user, $host, $serv ) };
    if ($@) {
        debugPrint( "crit", "Failed to process record, database said: $@" );
    }

    debugPrint( "info", "Added record for $nick!$user\@$host to $serv" );
}

sub get_records {
    my ( $type, $query, $serv, @return ) = @_;
    
    $count = 0; %data = (  );
    my %data = _r_search( $serv, $type, $query );
    for my $k ( keys %data ) {
        debugPrint( "info", "$type query for records on $query from server $serv returned: $k" );
        push @return, $k if $data{$k} eq 'nick';
    }
    return @return;
}

sub _r_search {
    my ( $serv, $type, @input ) = @_;
    return %data if $count > 1000;
    return %data if $count > Irssi::settings_get_str($IRSSI{name} . "_max_recursion");
    return %data if $count == 2 and ! Irssi::settings_get_bool( $IRSSI{name} . "_recursive_search" );

    debugPrint( "info", "Recursion Level: $count" );
    
    if ( $type eq 'nick' ) {
        $count++;
        for my $nick ( @input ) {
            next if exists $data{$nick};
            $data{$nick} = 'nick';
            my @hosts = _get_hosts_from_nick( $nick, $serv );
            _r_search( $serv, 'host', @hosts );
        }
    } elsif ( $type eq 'host' ) {
        $count++;
        for my $host ( @input ) {
            next if exists $data{$host};
            $data{$host} = 'host';
            my @nicks = _get_nicks_from_host( $host, $serv );
            verbosePrint( "Got nicks: " . join( ", ", @nicks ) . " from host $host" );
            _r_search( $serv, 'nick', @nicks );
        }
    }

    return %data;
}

sub _get_hosts_from_nick {
    my ( $nick, $serv, @return ) = @_;

    my $sth;
    if ( Irssi::settings_get_bool( $IRSSI{name} .  "_search_this_network_only" ) ){
        $sth = $DBH->prepare( "select host from records where nick = ? and serv = ?" );
        $sth->execute( $nick, $serv );
    } else {
        $sth = $DBH->prepare( "select host from records where nick = ?" );
        $sth->execute( $nick );
    }

    while ( my $row = $sth->fetchrow_hashref ) {
        push @return, $row->{host};
    }
    return @return;
}

sub _get_nicks_from_host {
    my ( $host, $serv, @return ) = @_;

    my $sth;
    if ( Irssi::settings_get_bool( $IRSSI{name} .  "_search_this_network_only" ) ){
        $sth = $DBH->prepare( "select nick from records where host = ? and serv = ?" );
        $sth->execute( $host, $serv );
    } else {
        $sth = $DBH->prepare( "select nick from records where host = ?" );
        $sth->execute( $host );
    }
    
    while ( my $row = $sth->fetchrow_hashref ) {
        if ( Irssi::settings_get_bool($IRSSI{name} . "_ignore_guest_nicks") ) {
            my $regex = Irssi::settings_get_str( $IRSSI{name} . "_guest_nick_regex" );
            next if $row->{nick} =~ m/$regex/i;
        }
        push @return, $row->{nick};
    }
    return @return;
}

# Handle printing.
sub debugPrint {
    # Short cut - instead of two debug statements thoughout the code,
    # we'll send all debugPrint's to the debugLog function as well

    windowPrint( $IRSSI{name} . " Debug: " . $_[1] )
        if Irssi::settings_get_bool($IRSSI{name} . "_debug");
    debugLog( $_[0], $_[1] );
}

sub verbosePrint {
    windowPrint( $IRSSI{name} . " Verbose: " . $_[0] )
        if Irssi::settings_get_bool($IRSSI{name} . "_verbose");
}

sub debugLog {
    my ( $lvl, $msg ) = @_;
    return unless Irssi::settings_get_bool($IRSSI{name} . "_debug_log" );
    my $now = strftime( "[%D %H:%M:%S]", localtime );

    my $logpath = Irssi::settings_get_str( $IRSSI{name} . "_debug_log_file" );
    if ( ! File::Spec->file_name_is_absolute($logpath) ) {
        $logpath = File::Spec->catfile( Irssi::get_irssi_dir(), $logpath );
    }

    open my $fh, ">>", $logpath
        or die "Fatal error: Cannot open my logfile at " . $IRSSI{name} . "_debug_log_file for writing: $!";
    print $fh "[$lvl] $now $msg\n";
    close $fh;
}

sub windowPrint {
    Irssi::active_win()->print( $_[0] );
}

windowPrint( "Loaded $IRSSI{'name'}" );

