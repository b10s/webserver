use warnings;
use strict;
use Socket qw(:DEFAULT :crlf);
use IO::Poll qw(POLLIN POLLOUT POLLERR POLLHUP);
use Time::HiRes qw(setitimer getitimer usleep ITIMER_REAL);

use Data::Dumper;

$|++;
$SIG{ALRM} = 'IGNORE';

# open server socket and set it up
my $server_port = 3024;
my $own_addr = pack_sockaddr_in($server_port, inet_aton('0.0.0.0'));
socket( my $server, PF_INET, SOCK_STREAM, (getprotobyname('tcp'))[2] );
setsockopt($server, SOL_SOCKET, SO_REUSEADDR, 1);
bind($server, $own_addr) or die "cant bind\n";
listen($server, SOMAXCONN);
$server->blocking(0);
$server->autoflush(1);
###################################


my %clients;

# new poll object
my $poll = IO::Poll->new();

# add server to poll for check status of socket
$poll->mask( $server=>POLLIN );

# main | event loop
while( 1 ) {
	$poll->poll();
	#print "\tpolled\n";

	# take all handles where was next events since last poll() : POLLIN | POLLHUP | POLLERR
	for my $handle ( $poll->handles( POLLIN | POLLHUP | POLLERR  ) ) {
		# get new connection
		if( $handle == $server ) {
			#print "server getting client\n";
			get_client_connections($handle);

		# otherwise we should react for some client which is ready to read\write
		} else {
			# read message from
			#print "get client name from ev loop\n";
			my $name = join(':', get_ip_port_by_handle($handle));
			#print "read data from $name\n";
			my $message = read_data( $name, $clients{$name}{data} );
			
			if( exists $message->{err} ) {
				print "err happens\n";
				process_error($message->{err}, \%clients, $name, $message->{msg});
				next;
			} else {
				# todo: need to make process procedure more safe to process some rubbish in message
				#print "going to process\n";
				process($name, $message->{msg});
			}
		}
	}

}

# just in case we can be out of event loop, but not, never
close($server);




########################################################################################################

sub get_client_connections {
	my $server = shift;
	# accept all clients
	while( accept(my $client, $server) ) {
		# serve client to be nice one
		$client->blocking(0);
		$client->autoflush(1);
		# get client ip and port
		my $name = join(':', get_ip_port_by_handle($client) );

		#print "$ip:$port\n";
		#exit;

		# save client socket and birthday in hash
		$clients{$name}{handle} = $client;
		$clients{$name}{birhday} = time;
		$clients{$name}{attempt_to_read} = 0;

		# add client to poll for react on ready to read\write
		$poll->mask($client=>POLLIN);
	}
}

# must void using this procedure cos it costs me time
sub get_ip_port_by_handle {
	my $handle = shift;
	my $other_end = getpeername($handle);
	my ($port, $iaddr) = unpack_sockaddr_in($other_end);
	return ( inet_ntoa($iaddr) , $port );
}

sub process_error {
	my ($err_code, $clients, $name, $message) = @_;
	# client name is string "ip:port"
	#print "get client name from process_error\n";
	my $handle = $clients{$name}{handle};

	# no data at all from client
	if ( $err_code == 1 ) {
		print "errod: client timeouted\n";
	} elsif ( $err_code == -1 ) {
		print "errod: client died\n";
		close_client($name);
		return;
	}

	

	# if client silent so long we are going to close it
	# 5 attempts or 2 seconds
	if( $clients{$name}{attempt_to_read} > 5  ) {
		print "going to close $name socket\n";
		close_client($name);
		return;
	}
}

sub read_data {
	my ( $name, $message) = @_;
	my ($buf, $read_res, $timer, $f, $handle);
	$handle = $clients{$name}{handle};
	$timer = 1;
	# set timer for read browser data
	setitimer(ITIMER_REAL, 0.005);
	# read until can read or until timer is done
	while( ($read_res=sysread($handle, $buf, 1024)) || ($timer=getitimer(ITIMER_REAL)) ) {
		$message.= $buf, $f++ if defined $read_res;
		last unless $read_res;
	}
	#print "readed: $read_res in $timer - $!\n";
	#print "message: $message\n" if $read_res;
	# for void interrupt for select() by SIG{ALRM} have to delete timer
	setitimer(ITIMER_REAL, 0);

	# client is closed by himself but before was polled as POLLIN | POLLHUP | POLLERR
	return { 'err' => -1 } if !$f;

	# timer is out, but client still put data: last read was successfull
	return { 'err'=>1 } if $f and $timer == 0;
	

	# data readed successfully
	return { 'msg'=>$message };
}

sub process {
	my ( $name, $message ) = @_;
	my $handle = $clients{$name}{handle};
	my %router = (
		"ip" => sub { return 1212121; },
		"test" => sub { return 'test'; },
	);

	#print Dumper \%clients,"\n";
	#exit;

	my ( $headers ) = split("\r\n\r\n", $message, 2);
	my ( $get ) = split("\r\n", $headers, 2);
	my $content;
	if ( $get=~/GET\s([^\s]+)\s/ ) {
		my $query_string = $1;
		$query_string=~s|^/||;
		$query_string=~s|/$||;

		# process known GET query
		if( exists $router{$query_string} ) {
			$content = &{$router{$query_string}};
			answer($handle, $content, 200);
		# process 404 for unknown GET query
		} else {
			answer($handle, 'Not found', 404);
		}
	# process not GET queries
	} else {
		$content = "<html>We can process only GET query, sorry.</html>";
		answer($handle, $content, 500);
	}

	# close processed client
	close_client($name);
}

sub close_client {
	my $name = shift;

	#print "going to close $name socket\n";
	$poll->mask( $clients{$name}{handle} => 0 );
	close $clients{$name}{handle};
	delete $clients{$name};
}

sub answer {
	my( $handle, $content, $status ) = @_;
	my $content_length = length $content;

	$handle->print("HTTP/1.1 $status\r\nServer: b10s\r\nConnection: close\r\nContent-Type: text/html\r\nContent-Length: ${content_length}\r\n\r\n${content}");
}