use warnings;
use strict;
use Socket;
use Time::HiRes qw(setitimer getitimer usleep ITIMER_REAL);

use Data::Dumper;

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

my %clients;

while( 1 ) {
	#print "iteration\n";
	my $done = 0;
	# за один проход цикла мы можем принять один коннект и положить его в список коннектов, 
	# предварительно сделав сокет клиента неблокирующим
	if( accept(my $client_conn, $server) ) {
		$client_conn->blocking(0);
		$client_conn->autoflush(1);

		my $other_end = getpeername($client_conn);
		my ($port, $iaddr) = unpack_sockaddr_in($other_end);
		my $actual_ip = inet_ntoa($iaddr);
		my $claimed_hostname = gethostbyaddr($iaddr, AF_INET);

		print "got new connection from $actual_ip : $port\n";
		$clients{"$claimed_hostname:$port"} = $client_conn;

		# если приняли коннект, то пропустим обработку коннекта, сначала примем ещё
		$done++;
	}

	for my $client_name ( keys %clients ) {
		#print "let's check $client_name\n";
		my $client = $clients{$client_name};

		my $message = read_data($client);

		if( exists $message->{err} ) {

			if( $message->{err}==-1 ) {
				print "$client_name leaves us\n";
				close $client;
				delete $clients{$client_name};
				next;
			} elsif ( $message->{err}==1 ) {
				print "$client_name reading timeout\n";
				next;
			}
			
		} else {
			process($client, $message->{msg});
			$done ++;
		}

	}
	

	next if $done;
	#print "going to sleep\n";
	usleep(500);
}

close($server);


sub read_data {
	my $client = shift;
	my ($buf, $read_res, $message, $timer);

	# ставим таймер в пол секунды
	setitimer(ITIMER_REAL, 0.5);
	while( $read_res = sysread($client, $buf, 1024) and  $timer=getitimer(ITIMER_REAL) ) {
		
		$message.= $buf;
	}

	# ошибка чтения, считаем, что клиент отвалился
	return { 'err'=>-1 } if not defined $read_res and not defined $message;
	
	# если кончилось время
	return { 'err'=>1 } if not $timer;
	
	return { 'msg'=>$message };
}

sub process {
	my ( $client, $message, $route ) = @_;
	#print $route, "\n";
	my %router = (
		"ip" => sub { return 1212121; },
		"test" => sub { return 'test'; },
	);


	my ( $headers ) = split("\r\n\r\n", $message, 2);
	my ( $get ) = split("\r\n", $headers, 2);
	my $content;
	print $get,"\n";
	if ( $get=~/GET\s([^\s]+)\s/ ) {
		my $query_string = $1;
		$query_string=~s|^/||;
		$query_string=~s|/$||;

		# process known GET query
		if( exists $router{$query_string} ) {
			$content = &{$router{$query_string}};
			answer($client, $content, 200);
		# process 404 for unknown GET query
		} else {
			answer($client, 'Not found', 404);
		}
	# process not GET queries
	} else {
		$content = "<html>We can process only GET query, sorry.</html>";
		answer($client, $content, 200);
	}	
}

sub answer {
	my( $client, $content, $status ) = @_;
	my $content_length = length $content;

	$client->print("HTTP/1.1 $status\r\nConnection: close\r\nServer: b10s\r\nContent-Type: text/html\r\nContent-Length:$content_length\r\n\r\n$content");
}