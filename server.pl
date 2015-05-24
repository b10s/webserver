use warnings;
use strict;
use Socket;
use Time::HiRes;

use Data::Dumper;

socket( my $server, PF_INET, SOCK_STREAM, (getprotobyname('tcp'))[2] );
setsockopt($server, SOL_SOCKET, SO_REUSEADDR, 1);
$server->blocking(0);
$server->autoflush(1);

my $server_port = 3024;
my $own_addr = pack_sockaddr_in($server_port, inet_aton('0.0.0.0'));
bind($server, $own_addr) or die "cant bind\n";
listen($server, SOMAXCONN);

my %clients;
#my $read_timeout = 1;


while( 1 ) {
	#print "iteration\n";
	my $done = 0;
	# за один проход цикла мы можем принять один коннект и положить его в список коннектов, предварительно сделав сокет клиента неблокирующим
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
		my $buf;
		my $read_res = sysread($client, $buf, 1024);
		# клиент на связи но молчит :)
		next if not defined $read_res;

		# клиент отпал
		if( $read_res==0 ) {
			print "$client_name leaves us\n";
			delete $clients{$client_name};
		}

		# началось чтение
		if ( $read_res ) {
			my $message.= $buf;
			my $read_starts = time;
			# читаем пока читается или пока не вышел таймаут
			until ( $buf ) {
				$message.= $buf if sysread($client, $buf, 1024);
			}

			process($client, $message);
			close $client;
			delete $clients{$client_name};
			#shutdown($client, 0);
			#print "$client_name leaves us\n";

			$done++;
		}

	}
	

	next if $done;
	#print "going to sleep\n";
	#select();
	Time::HiRes::usleep(500);
}

close($server);


sub process {
	my $client = shift;
	my $message = shift;
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