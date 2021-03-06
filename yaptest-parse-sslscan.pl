#!/usr/bin/env perl
use strict;
use warnings;
use POSIX;
use Getopt::Long;
use yaptest;
use File::Basename;

my $script_name = basename($0);
my $usage = "Usage: $script_name sslscan-10.0.0.1-443.out [ sslscan-10.0.0.2-443.out ]

Parses sslscan output for weak ciphers and adds issues to databases.  IP and port must be in the filename.
";

my $file = shift or die $usage;
unshift @ARGV, $file;

my $y = yaptest->new();

while (my $filename = shift) {
	print "Processing $filename ...\n";

	unless ($filename =~ /(\d+\.\d+\.\d+\.\d+)-(\d+)/) {
		print "WARNING: Filename $filename doesn't contain an IP address and port.  Skipping...\n";
		next;
	}
	my $ip = $1;
	my $port = $2;
	print "IP: $ip, PORT: $port\n";

	unless (open(FILE, "<$filename")) {
		print "WARNING: Can't open $filename for reading.  Skipping...\n";
		next;
	}

	my $fs_supported = 0;
	my $only_fs_supported = undef;
	while (<FILE>) {
		# print;
		chomp;
		my $line = $_;

		# Accepted  SSLv2  128 bits  RC2-CBC-MD5
		if ($line =~ /^\s*Accepted.*SSLv2\s+\d+/) {
			print "PARSED: SSLv2 supported: $line\n";

			$y->insert_issue(name => "sslv2_supported", ip_address => $ip, port => $port, transport_protocol => 'TCP');
		}
		
		# Accepted  TLSv1  40 bits   EXP-DES-CBC-SHA
		if ($line =~ /^\s*Accepted.*(SSLv2|TLSv1|SSLv3)\s+(40|56)\s+/) {
			print "PARSED: Weak Cipher: $line\n";

			$y->insert_issue(name => "ssl_weak_ciphers", ip_address => $ip, port => $port, transport_protocol => 'TCP');
		}

		# Accepted  TLSv1  256 bits  ADH-AES256-SHA
		if ($line =~ /^\s*Accepted.*(SSLv2|TLSv1|SSLv3)\s+(\d+)\s+bits\s+(ADH|AECDH)-/) {
			print "PARSED: Weak Cipher: $line\n";

			$y->insert_issue(name => "ssl_anon_dh", ip_address => $ip, port => $port, transport_protocol => 'TCP');
		}

		
		if ($line =~ /^\s*Accepted.*(SSLv2|TLSv1|SSLv3)\s+(\d+)\s+bits\s+/) {
			if (not defined($only_fs_supported)) {
				$only_fs_supported = 1;
			}
			# Accepted  TLSv1  256 bits  EDH-AES256-SHA
			if ($line =~ /^\s*Accepted.*(SSLv2|TLSv1|SSLv3)\s+(\d+)\s+bits\s+(ECDHE|DHE|EDH)-/) {
				print "PARSED: Forward-secrecy cipher suite: $line\n";
				$fs_supported = 1;
			} else {
				$only_fs_supported = 0;
			}

		}
	}
	if (not $fs_supported) {
		$y->insert_issue(name => "ssl_fs_not_supported", ip_address => $ip, port => $port, transport_protocol => 'TCP');
	} elsif (not $only_fs_supported) {
		$y->insert_issue(name => "ssl_fs_not_mandated", ip_address => $ip, port => $port, transport_protocol => 'TCP');
	}
}
$y->commit;
$y->destroy;
