package confluence;

#use strict;
use warnings;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use MIME::Base64;
use utf8;

my $ua;

sub new {
	my $class = shift;
	my %arg = @_;
	return "No URL defined" unless $arg{Url};
	my $basic;
	if ( $arg{Login} && $arg{Login} ne '' && $arg{Password} && $arg{Password} ne '') {
		$basic = 'Basic '.encode_base64($arg{Login}.":".$arg{Password});
	} elsif ( $arg{Token} && $arg{Token} ne '' ) {
		$basic = 'Bearer '.$arg{Token};
	}
	my $self;
	print "Token".$arg{Token}.",Login".$arg{Login}."\n";
	$ua = LWP::UserAgent->new;
	$ua->timeout(60);
	$ua->ssl_opts(
  	SSL_verify_mode => 0, #IO::Socket::SSL::SSL_VERIFY_NONE, 
  	verify_hostname => 0
	);
	print $arg{Url}.'/rest/api/latest/content?spaceKey='.$arg{Space}.'&expand=ancestors'."\n"."Authorization => ".$basic."\n";
	my $response = $ua->get($arg{Url}.'/rest/api/latest/content?spaceKey='.$arg{Space}.'&expand=ancestors', Authorization => $basic);
	if ($response->is_success) {
		print "Logged to Confluence successfully\n" if ($arg{Debug});
		$self = { basic => $basic, url => $arg{Url}, space => $arg{Space}, debug => $arg{Debug} };
		my $answer = decode_json $response->decoded_content;
		if (scalar @{$answer->{results}}) {
			print "Space ".$arg{Space}." found \n";
			foreach ( @{$answer->{results}} ) {
				if ( ! scalar @{$_->{ancestors}} ) {
					print "The space home is \"".$_->{title}."\" with id ".$_->{id}."\n";
					$self->{home} = $_->{id};
					last;
				}
			}
		}
		else {
			print "Space ".$arg{Space}." not found \n";
			return;
		}
	} else {
		#print "Login to Confluence was unsuccessfull\n";
		print $response->status_line;
		return;
	}
	bless $self, $class;
}

sub createContent {
	my $self = shift;
	my %arg = @_;
	my %data = %{$arg{Content}};
	unless (defined $data{ancestors}) {
		$data{ancestors} = [ { id => $self->{home} } ];
	}
	my $content = encode_json \%data;
	print $content."\n" if ($self->{debug});
	my $basic = ($arg{Login} && $arg{Password}) ? 'Basic '.encode_base64($arg{Login}.":".$arg{Password}) : ($arg{Token}) ? 'Bearer '.$arg{Token}:$self->{basic};

	my $response = $ua->post($self->{url}.'/rest/api/content', Authorization => $basic, 'Content-Type' => 'application/json; charset=UTF-8', 'Content' => $content);
	if ($response->is_success) {
		print $response->status_line."\n" if ($self->{debug});
		print $response->decoded_content."\n" if ($self->{debug});
		my $answer = decode_json $response->decoded_content;
		return $answer->{id};
	} else {
		print "Got error while creating content\n";
		print $response->status_line."\n";
		print $response->decoded_content."\n";
	}
	return;
}

sub addAttachments {
	my $self = shift;
	my %arg = @_;
	foreach my $file (@{$arg{Files}}) {
		my $filesize = -s $file;
		if ( $filesize > 10485760 ) {
			print "The file size exceeds the maximum permitted size of 10485760 bytes";
			return 1;
		}
		my $response = $ua->post($self->{url}.'/rest/api/latest/content/'.$arg{Id}.'/child/attachment', Authorization => 'Basic '.$self->{basic}, 'Content_Type' => 'multipart/form-data', Content => [file => [$file]], 'X-Atlassian-Token' => 'no-check');
		if ($response->is_success) {
			print $response->status_line."\n";
			print $response->decoded_content;
		} else {
			print "Got error while uploading files\n";
			print $response->status_line."\n";
			print $response->decoded_content."\n";
			return;
		}
	}
	return 1;
}


1;
