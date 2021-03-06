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
	my $done = 0;
	# my ($nfound, $timeleft) = select($rout=$rbits, undef, undef, 0.5);

	#print unpack("b*", $rout), "\n";
	#print unpack("b*", $rbits), "\n";
	#print "select, nfound: $nfound, timeleft: $timeleft, rout: $rout, rbits: $rbits \n";
	#print $!,"\n" if $nfound == -1;
	#print "iteration\n";
	#if($nfound) {
	#	print unpack("b*", $rout), "\n";
	#	print unpack("b*", $server_bit_mask), "\n";
	#	print unpack("b*", $rout & $server_bit_mask), "\n";
	#}
	

	#if ( defined $rout && $server_bit_mask & $rout ) {
	#	print "server socket ready for read!\n";
	#}

	# in one iteration we can get one connection from client and put it to pool of connections
	# but before set socket as not blocked

	if( accept(my $client_conn, $server) ) {
		$client_conn->blocking(0);
		$client_conn->autoflush(1);

		my $other_end = getpeername($client_conn);
		my ($port, $iaddr) = unpack_sockaddr_in($other_end);
		my $actual_ip = inet_ntoa($iaddr);
		my $claimed_hostname = gethostbyaddr($iaddr, AF_INET);

		print "got new connection from $actual_ip : $port\n";
		$clients{"$claimed_hostname:$port"}{handler} = $client_conn;

		$done++;
		#next;
	}

	for my $client_name ( keys %clients ) {
		print "let's check $client_name\n";
		my $client = $clients{$client_name}{handler};

		my $message = read_data($client, $clients{$client_name}{data} );
		#print "client told: $message->{msg}\n";
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
					close $client;
					delete $clients{$client_name};
			}
			next;
		} else {
			# todo: need to make process procedure more safe to process some rubbish in message
			process($client, $message->{msg});
			print "$client_name get answer and will be closed \n";
			# maybe i dont need to close connection
			close $client;
			delete $clients{$client_name};
			$done ++;
		}

	}
	

	# dont need to sleed if we done some work before
	next if $done;
	#print "going to sleep \n";
	usleep(500);
}

close($server);


sub read_data {
	my ( $client, $message) = @_;
	my ($buf, $read_res, $timer, $f);

	# set timer for read browser data
	setitimer(ITIMER_REAL, 0.005);
	while( ($read_res=sysread($client, $buf, 1024)) || ($timer=getitimer(ITIMER_REAL)) ) {
		$message.= $buf if $read_res;
		$f++, last if $message=~/$CRLF$/;
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