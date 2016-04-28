package Export::dokuwiki;

use strict;
use warnings;
use utf8;
#use Encode;
use Data::Dumper;

sub export {
	my $conf = shift;
	my $debug = shift;
	my $data;
	my $files = readDir($conf->{pages}, $debug);
	foreach (@{$files}) {
		open (my $fh, '<', $conf->{pages}.'/'.$_.'.txt') || die;
		{
			local $/;
			$data->{$_}->{body} = <$fh>;
		}
		close $fh;
	}

	unless ($data->{$conf->{startPage}}->{body}) {
		print "The start page \"".$conf->{startPage}."\" was not found in Dokuwiki\n";
		exit;
	}

	$data->{$conf->{startPage}}->{parent} = '_ROOT_';
	buildTree(\$data, $conf->{startPage}, 0, $debug);

	print "Orphaned pages:\n";
	foreach (sort keys %{$data}) {
		unless ($data->{$_}->{parent}) {
			print $_."\n";
		}
	}
	print "\nCheck for attachments:\n\n";
	foreach (sort keys %{$data}) {
		$data->{$_}->{body} = translateMarkup($data->{$_}->{body}, $debug);
		while ($data->{$_}->{body} =~ /\!(\S+?)\!/g) {
			my $image= $1;
			$image =~ s/\|.*$//;
			next if ($image =~ /\:\/\//); # Skip external links
				if ( -e $conf->{media}.'/'.$image ) {
					print "Found attachment: ".$conf->{media}.'/'.$image." on page $_\n" if ($debug);
					push @{$data->{$_}->{attachments}}, $conf->{media}.'/'.$image;
				} else {
					print "Attachment not found: ".$conf->{media}.'/'.$image." on page $_\n";
				}
		}
	}

	return $data;
}

sub buildTree {
	my $dataRef = shift;
	my $data = ${$dataRef};
	my $start = shift;
	my $depth = shift;
	my $debug = shift;
	print "\n" . "\t" x $depth . "Building tree for page $start\n" if ($debug);
	my $links = getInternalLinks($data->{$start}->{body});
	print "\t" x $depth . join(',',@{$links}) ."\n" if ($debug);
	foreach my $link (@{$links}) {
		if (defined $data->{$link}) {
			next if defined $data->{$link}->{parent};
			$data->{$link}->{parent} = $start;
			buildTree(\$data, $link, $depth + 1, $debug);

		}
	}
}

sub getInternalLinks {
	my $text = shift;
	my @links;
	while ( $text =~ /\[\[(.+?)\]\]/g ) {
		my $link = $1;
		next if ($link =~ /\:\/\//); # Skip external links
			$link =~ s/[\/\.\,]/\_/g;
		$link =~ s/^\://;
		$link =~ s/\:/\//g;
		$link =~ s/\s/\_/g;
		$link =~ s/\|.*$//; # Remove link text. Maybe we'll use it later.
			$link =~ s/[^0-9a-zA-Z]+$//;
		push @links, lc($link);
	}
	return \@links;
}

sub readDir {
	my $dir = shift;
	my $debug = shift;
	my @files;
	print "Traversing directory $dir\n" if ($debug);
	opendir (my $dh, $dir) || die;
	while (readdir $dh) {
		my $file = $_;
		if (/^(.+)\.txt$/) {
			push @files, $1;	
		}
		elsif (-d $dir.'/'.$file) {
			next if ( $file =~ /\.$/ );
			my $subFolder = readDir($dir.'/'.$file);
			for (@{$subFolder}) {
				$_ = $file.'/'.$_;
			}
			push @files, @{$subFolder};
		}
	}
	closedir $dh;
	return \@files;
}

sub translateMarkup {
	my $page = shift;
	my $debug = shift;

	# Change line breaks
	$page =~ s/\\\\/\n/g;

	# Change attached images
	$page =~ s/\{\{[\:]*([^\|\{\}]+).*?\}\}/\!$1\!/g;
	$page =~ s/\!([^\!\s]+?)\?(\d+)\!/\!$1\|width=$2\!/g;
	$page =~ s/\!([^\!\s]+?)\?\S*\!/\!$1\!/g;
	$page =~ s/(.)(\!.+?\!)/$1\n$2/g; # add new line before the attachment
	$page =~ s/(\!.+?\!)(.)/$1\n$2/g; # add new line after the attachment
	$page =~ s/\!url\>/\!/g;

	# Hide curly brackets
	$page =~ s/([\{\}])/\\$1/g;

	# Change links
	$page =~ s/\[\[\:?(.+?)\]\]/\[$1\]/g;
	$page =~ s/\[(.+?)\|(.+?)\]/\[$2\|$1\]/g;

	# Change headings
	$page =~ s/(\n|^)\={6}(.+?)\={6,}/$1h1. $2/gs;
	$page =~ s/(\n|^)\={5}(.+?)\={5,}/$1h2. $2/gs;
	$page =~ s/(\n|^)\={4}(.+?)\={4,}/$1h3. $2/gs;
	$page =~ s/(\n|^)\={3}(.+?)\={3,}/$1h4. $2/gs;
	$page =~ s/(\n|^)\={2}(.+?)\={2,}/$1h5. $2/gs;
	$page =~ s/(\n|^)\={1}(.+?)\={1,}/$1h6. $2/gs;

	# Text effects
	$page =~ s/\*\*\s*(.+?)\s*\*\*/\*$1\*/gs; # bold
	$page =~ s/__\s*(.+?)\s*__/\+$1\+/gd; # underline
	$page =~ s/(^|\n|\s)\/\/\s*(.+?)\s*\/\//$1_$2_/gs; # italic
	$page =~ s/\'\'\s*(.+?)\s*\'\'/\{\{$1\}\}/gs; # monospace
	$page =~ s/<del>\s*(.+?)\s*<\/del>/-$1-/gs; # strikethrough
	$page =~ s/<sub>\s*(.+?)\s*<\/sub>/~$1~/gs; # subscript
	$page =~ s/<sup>\s*(.+?)\s*<\/sup>/\^$1\^/gs; # superscript

	# translate note macro
	$page =~ s/\<note\>(.+?)\<\/note\>/\{note\}$1\{note\}/gs;
	$page =~ s/\<note tip\>(.+?)\<\/note\>/\{tip\}$1\{tip\}/gs;
	$page =~ s/\<note important\>(.+?)\<\/note\>/\{warning\}$1\{warning\}/gs;
	$page =~ s/\<code\>(.+?)\<\/code\>/\{code\}$1\{code\}/gs;

	# Tables
	# Headers
	my %tableHeaderReplace;
	while ($page =~ /(\n|^)((\^.+?)+\s*\|)\s*\n\|/g) {
		my $tableHeader = $2; 
		(my $newTableHeader = $tableHeader) =~ s/\s*\^\s*/\|\|/g;
		$newTableHeader =~ s/\s*\|$/\|\|/;
		$tableHeaderReplace{$tableHeader} = $newTableHeader;
	}

	foreach (keys %tableHeaderReplace) {
		(my $fromPattern = $_) =~ s/\^/\\\^/g;
		$fromPattern =~ s/\|/\\\|/g;
		(my $toPattern = $tableHeaderReplace{$_}) =~ s/\^/\\\^/g;
		print "/$fromPattern/$toPattern/\n";
		$page =~ s/$fromPattern/$toPattern/;
	}

	return $page;
}

1;
