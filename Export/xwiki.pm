package Export::xwiki;

use strict;
use warnings;
use utf8;
use Data::Dumper;
use XML::Parser;
use MIME::Base64;

our $xml;
our $isAttachment = 0;

sub export {
	my $conf = shift;
	my $debug = shift;
	my $data;
	my $files = readDir($conf->{pages}, $debug);
	foreach (@{$files}) {
		open (my $fh, '<', $conf->{pages}.'/'.$_.'.xml') || die;
		{
			local $/;
			(my $page = $_ ) =~ s/^.+\///;
			my $fileContent = <$fh>;
			my $parser = XML::Parser->new();
			$parser->setHandlers( Start => \&startElement, Char => \&characterData );
			undef $xml;
			$parser->parse($fileContent);
			if ($page eq 'WebHome') {
				my $parent;
				my $name = $xml->{parent};
				if ($xml->{fullparent} =~ /([^\.]+)\.[^\.]+$/) {
					$parent = $1;
				} else {
					$parent = 'start';
				}
				$xml->{parent} = $parent;
				$data->{$name} = $xml;
			} else {
				$data->{$page} = $xml;
			}
		}
		close $fh;
	}

	$data->{start}->{parent} = '_ROOT_';
	$data->{start}->{body} = 'Content migrated from XWiki';

	print "\nTranslating markup:\n\n";
	foreach (sort keys %{$data}) {
		$data->{$_}->{body} = translateMarkup($data->{$_}->{body}, $debug);
	}
#print Dumper($data); exit;
#print $data->{'Handling EOLs'}->{body}; exit;
	return $data;
}

sub readDir {
	my $dir = shift;
	my $debug = shift;
	my @files;
	print "Traversing directory $dir\n" if ($debug);
	opendir (my $dh, $dir) || die;
	while (readdir $dh) {
		my $file = $_;
		if (/^(.+)\.xml$/) {
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

	# Line breaks
	$page =~ s/\|\\\\\s*\n/\|\n/g; # If a line breaks in the table row
		$page =~ s/\\\\/\n/g;

	# Remove text styles
	$page =~ s/\(\%.*?\%\)//gs;

	# Change headings
	$page =~ s/(\n|^)\={6}(.+?)\={6,}/$1h6. $2/gs;
	$page =~ s/(\n|^)\={5}(.+?)\={5,}/$1h5. $2/gs;
	$page =~ s/(\n|^)\={4}(.+?)\={4,}/$1h4. $2/gs;
	$page =~ s/(\n|^)\={3}(.+?)\={3,}/$1h3. $2/gs;
	$page =~ s/(\n|^)\={2}(.+?)\={2,}/$1h2. $2/gs;
	$page =~ s/(\n|^)\={1}(.+?)\={1,}/$1h1. $2/gs;

	# Attached images
	$page =~ s/\[\[image\:(.+?)\]\]/\!$1\!/g;
	$page =~ s/\!([^\!]+?)\|\|([^\!]+?\=[^\!]+?)\!/\!$1\|$2\!/g;

	# Change links
	$page =~ s/\[\[\:?(.+?)\]\]/\[$1\]/g;
	$page =~ s/\[([^\]]+?)\|\|.+?\]/\[$1\]/g;
	$page =~ s/\[(.+?)\|(.+?)\]/\[$2\|$1\]/g;
	$page =~ s/\[(.+?)\>\>attach\:(.+?)\]/\[\^$2\]/g;
	$page =~ s/\[(.+?)\>\>doc\:(.+?)\]/\[$1\|$2\]/g;
	$page =~ s/\[(.+?)\>\>url\:(.+?)\]/\[$1\|$2\]/g;
	$page =~ s/\[(.+?)\>\>(.+?)\]/\[$1\|$2\]/g;

	# Text effects
	$page =~ s/\*\*\s*(.+?)\s*\*\*/\*$1\*/gs; # bold
	$page =~ s/__\s*(.+?)\s*__/\+$1\+/gd; # underline
	$page =~ s/(^|\n|\s)\/\/\s*(.+?)\s*\/\//$1_$2_/gs; # italic
	$page =~ s/\#\#\s*(.+?)\s*\#\#/\{\{$1\}\}/gs; # monospace
	$page =~ s/\-\-\s*(.+?)\s*\-\-/-$1-/g; # strikethrough
	$page =~ s/\,\,\s*(.+?)\s*\,\,/~$1~/gs; # subscript
	$page =~ s/\^\^\s*(.+?)\s*\^\^/\^$1\^/gs; # superscript

	# Code macro
	$page =~ s/\{\{code\}\}(.+?)\{\{code\}\}/\{code\}$1\{code\}/gs;
	$page =~ s/\{\{code\}\}(.+?)\{\{\/code\}\}/\{code\}$1\{code\}/gs;
	$page =~ s/\{\{code\s(.+?)\}\}(.+?)\{\{code\}\}/\{code\:$1\}$2\{code\}/gs;

	$page =~ s/\<code\>(.+?)\<\/code\>/\{code\}$1\{code\}/gs;
	$page =~ s/\{\{\{(.+?)\}\}\}/\{code\}$1\{code\}/gs;
	$page =~ s/\{\{toc\/?\}\}/\{toc\}/g;

	# Other
	$page =~ s/\~\~\//\//g;
	$page =~ s/\~\//\//g;
	$page =~ s/(^|\n)\~1\./$1 1\./gs;
	$page =~ s/\n\#/\n\\\#/gs; # escape hash to avoid numbered list creation
	$page =~ s/(^|\n)1\./$1\#/gs;

	# Hide curly brackets
	$page =~ s/([\{](?!toc|code|noformat))/\\$1/g;

	# Tables
	# Headers
	my %tableHeaderReplace;
	while ($page =~ /(\n|^)((\|\=.+?)+\s*\|?)\s*\\?\\?\s*\n\|/g) {
		my $tableHeader = $2;
		(my $newTableHeader = $tableHeader) =~ s/\s*\|\=\s*/\|\|/g;
		$newTableHeader =~ s/\s*\|?$/\|\|/;
		$tableHeaderReplace{$tableHeader} = $newTableHeader;
	}

	foreach (keys %tableHeaderReplace) {
		(my $fromPattern = $_) =~ s/\=/\\\=/g;
		$fromPattern =~ s/\|/\\\|/g;
		(my $toPattern = $tableHeaderReplace{$_}) =~ s/\^/\\\^/g;
		print "/$fromPattern/$toPattern/\n";
		$page =~ s/(\n|^)$fromPattern/$1$toPattern/g;
	}

	return $page;
}

sub startElement {
	my ( $parseinst, $element, %attrs ) = @_;
	if ($element eq 'xwikidoc') {
		$isAttachment = 0;
	} elsif ($element eq 'attachment') {
		$isAttachment = 1;
	}
}

sub characterData {
	my ( $parseinst, $cdata ) = @_;
	my $context = $parseinst->{Context}->[-1];
	if (! $isAttachment && $context eq 'content') {
		$xml->{body} .= $cdata;
	}
	elsif (! $isAttachment && $context eq 'web') {
		$xml->{fullparent} = $cdata;
		$cdata =~ s/^.*\.//;
		$xml->{parent} = $cdata;
	}
	elsif ($isAttachment && $context eq 'filename') {
		$isAttachment = $cdata;
		push @{$xml->{attachments}}, '/tmp/'.$isAttachment;
	}
	elsif ($isAttachment && $context eq 'content') {
		open (my $f, '>:raw', '/tmp/'.$isAttachment) or die "Unable to open: $!";
		print $f decode_base64($cdata);
		close $f;
	}
}


1;
