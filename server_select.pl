use warnings;
use strict;
use Socket qw(:DEFAULT :crlf);
use Time::HiRes qw(setitimer getitimer usleep ITIMER_REAL);

use Data::Dumper;

my %clients;


$SIG{ALRM} = sub { };
$|++;

socket( my $server, PF_INET, SOCK_STREAM, (getprotobyname('tcp'))[2] );
setsockopt($server, SOL_SOCKET, SO_REUSEADDR, 1);
$server->blocking(0);
$server->autoflush(1);

my $server_port = 3024;
my $own_addr = pack_sockaddr_in($server_port, inet_aton('0.0.0.0'));
bind($server, $own_addr) or die "cant bind\n";
listen($server, SOMAXCONN);



my ( $server_bit_mask, $rbits, $rout );
vec($server_bit_mask, fileno($server), 1) = 1;
$rbits = $server_bit_mask;

while( 1 ) {
	# wait until data from client is ready
	my ($nfound, $timeleft) = select($rout=$rbits, undef, undef, undef);

	if ( defined $rbits && ( $server_bit_mask & $rout ) ) {
		print "\tserver socket ready for read!\n";
		while( accept(my $client_conn, $server) ) {
			$client_conn->blocking(0);
			$client_conn->autoflush(1);

			my $other_end = getpeername($client_conn);
			my ($port, $iaddr) = unpack_sockaddr_in($other_end);
			my $actual_ip = inet_ntoa($iaddr);
			my $claimed_hostname = gethostbyaddr($iaddr, AF_INET);

			print "\tgot new connection from $actual_ip : $port\n";
			$clients{"$claimed_hostname:$port"}{handler} = $client_conn;
			vec($clients{"$claimed_hostname:$port"}{bitmask}, fileno( $client_conn ), 1) = 1;
			$clients{"$claimed_hostname:$port"}{birhday} = time;

			vec($rbits, fileno($client_conn), 1) = 1;
		}
	}

	for my $client_name ( keys %clients ) {
		print "let's check $client_name\n";
		my $client = $clients{$client_name}{handler};
		# if clients socket not ready for be readed
		if( not $clients{$client_name}{bitmask} & $rout ) {
			# if client socket for 4+ seconds keep silent we close it
			if( time - $clients{$client_name}{birhday} > 4 ) {
				print "$client_name timeouted \n";
				vec($rbits, fileno($client), 1) = 0;
				close $client;
				delete $clients{$client_name};
			}
			next;
		}

		my $message = read_data($client, $clients{$client_name}{data} );

		if( exists $message->{err} ) {

			if( $message->{err}==-1 ) {
				print "$client_name say nothing \n";
				# todo: in case client say it again we should close connection
				# check next client
			} elsif ( $message->{err}==1 ) {
				print "hope dont get there until can detect end of message \n";
				#print "$client_name reading timeout\n";

				#close $client;
				#delete $clients{$client_name};

				# check next client
			} elsif ( $message->{err}==0 ) {
				$clients{$client_name}{data}.=$message;
			}

			$clients{$client_name}{attempt_to_read}++;
			if( $clients{$client_name}{attempt_to_read} > 5 ) {
					print "$client_name timeouted \n";
					vec($rbits, fileno($client), 1) = 0;
					close $client;
					delete $clients{$client_name};
			}
			next;
		} else {
			# todo: need to make process procedure more safe to process some rubbish in message
			process($client, $message->{msg});
			print "$client_name get answer and will be closed \n";
			# maybe i dont need to close connection
			vec($rbits, fileno($client), 1) = 0;
			close $client;
			delete $clients{$client_name};
		}

	}
}

close($server);


sub read_data {
	my ( $client, $message) = @_;
	my ($buf, $read_res, $timer, $f);

	# set timer for read browser data
	setitimer(ITIMER_REAL, 0.005);
	while( ($read_res=sysread($client, $buf, 1024)) || ($timer=getitimer(ITIMER_REAL)) ) {
		$message.= $buf if $read_res;
		$f++, last if defined $message and $message=~/$CRLF$/;
		# todo: must detect end of message before time out, now i cant :( and hope browser send me all in short time
	}

	# for void interrupt for select() by SIG{ALRM} have to delete timer
	setitimer(ITIMER_REAL, 0);

	# nothing get from client in while
	return { 'err'=>-1 } if not defined $message and ( not defined $read_res or $read_res == 0 );

	# we got some data from client but incomplite for GET request
	if ( !$f ) {
		return { err=>0, msg=>$message };
	}
	#print "we readed: read_res: $read_res, message: $message\n";
	
	# timer is out, but client still put data
	# todo: since i cant detect end of data client can send any data and we have to be timeouted
	# return { 'err'=>1 } if not $timer;
	
	return { 'msg'=>$message };
}

sub process {
	my ( $client, $message ) = @_;

	my %router = (
		"ip" => sub { return 1212121; },
		"test" => sub { return 'test'; },
	);


	my ( $headers ) = split("\r\n\r\n", $message, 2);
	my ( $get ) = split("\r\n", $headers, 2);
	my $content;
	#print $get,"\n";
	if ( $get=~/GET\s([^\s]+)\s/ ) {
		my $query_string = $1;
		$query_string=~s|^/||;
		$query_string=~s|/$||;

		# process known GET query
		if( exists $router{$query_string} ) {
			$content = &{$router{$query_string}};
			#print $content, "\n";
			#exit;
			answer($client, $content, 200);
		# process 404 for unknown GET query
		} else {
			answer($client, 'Not found', 404);
		}
	# process not GET queries
	} else {
		$content = "<html>We can process only GET query, sorry.</html>";
		answer($client, $content, 500);
	}	
}

sub answer {
	my( $client, $content, $status ) = @_;
	my $content_length = length $content;

	$client->print("HTTP/1.1 $status\r\nServer: b10s\r\nConnection: close\r\nContent-Type: text/html\r\nContent-Length: ${content_length}\r\n\r\n${content}");
}