#!/usr/bin/perl

use strict;
use warnings;
use vars qw($fromWiki %confluence %dokuwiki %xwiki);
require "config.pl";
require confluence;
use Data::Dumper;
use Getopt::Long;
use utf8;

my ($skip, $maxpages, $debug);
Getopt::Long::Configure('bundling');
GetOptions(
		"skip=s"      => \$skip,
		"maxpages=i"  => \$maxpages,
		"debug"       => \$debug
		);

my $module = "Export/$fromWiki.pm";
if (eval { require $module; 1; }) {
	print "Module $fromWiki.pm loaded ok\n" if ($debug);
} else {
	print "Could not load $fromWiki.pm. Error Message: $@\n";
	exit;
}

no strict 'refs';
my $data = "Export::${fromWiki}::export"->(\%$fromWiki, $debug);

print "\nConnection to Confluence\n\n";
my $cfl = confluence->new( Url      => $confluence{url},
		Login    => $confluence{login},
		Password => $confluence{password},
		Space    => $confluence{space},
		Debug    => $debug,
		);

unless ($cfl) {
	die "Error while connecting to Confluence";
}

my $count;
my $rootId;
my $orphanedId;
my $lastIteration = 0;
while (! $lastIteration ) {
	$lastIteration = 1;	
	foreach my $page (sort keys %{$data}) {
		next if ($data->{$page}->{imported});
		if ( ! defined $data->{$page}->{parent} && ! defined $orphanedId && ! defined $skip ) {
			next unless ($rootId); # Skip orphaned page because we have not created the root page yet
				my %content = (
						type => 'page',
						title => 'Orphaned pages',
						space => { key => $confluence{space} },
						body => { storage => { value => 'Pages with absent ancestors', representation => 'storage' } },
						ancestors => [ { id => $rootId } ]
						);
			my $id = $cfl->createContent(Content => \%content) || die "Failed creating content";
			if ( $id =~ /^\d+$/) {
				$orphanedId = $id;
			}
		} elsif ( ( ! defined $data->{$page}->{parent} && defined $orphanedId )
				|| $data->{$page}->{parent} eq '_ROOT_' || $data->{$data->{$page}->{parent}}->{imported}) {
			next if ($page eq '_ROOT_');
			print "\n\n-----------------------\n\nImporting page $page\n";
			if (defined $skip && $page eq $skip) {
				$skip = '';
				next;
			}
			if (defined $skip && $skip) {
				print "Skipping this page\n";
				next;
			}

			my $representation = 'wiki';
			if (defined $data->{$page}->{body} && $data->{$page}->{body} =~ /^<html/i) {
				$representation = 'storage';
			}
			my %content = (
					type => 'page',
					title => (defined $data->{$page}->{parent} && $data->{$page}->{parent} eq '_ROOT_' && defined $confluence{rootPage})?$confluence{rootPage}:$page,
					space => { key => $confluence{space} },
					body => { storage => { value => $data->{$page}->{body}, representation => $representation } },
					);

			if ( ! defined $data->{$page}->{parent} && defined $orphanedId ) {
				$content{ancestors} = [ { id => $orphanedId } ];
			} elsif ($data->{$data->{$page}->{parent}}->{imported}) {
				$content{ancestors} = [ { id => $data->{$data->{$page}->{parent}}->{imported} } ];
			}

			my $id = $cfl->createContent(Content => \%content) || die "Failed creating content $page";
			if ( $id =~ /^\d+$/) {
				print "Got page id $id\n";
				$data->{$page}->{imported} = $id;
				$count++;
				$lastIteration = 0;
				$rootId ||= $id; # This definitely will be the root page
					if (defined $data->{$page}->{attachments}) {
						print "Page has attachments\n";
						unless ($cfl->addAttachments(Files => \@{$data->{$page}->{attachments}}, Id => $id)) {
							print "Cannot upload attachment to $id";
						}
					}
			} else {
				print "Got wrong id: $id. Exiting...\n";
				exit;
			}
			last if ($maxpages && $count >= $maxpages);
		}
	}
}
