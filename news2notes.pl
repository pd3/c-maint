#!/usr/bin/perl
use warnings;
use strict;
use Getopt::Long;
use Text::Wrap;

sub usage {
    my ($exit_code) = @_;
    print STDERR "Usage: $0 -format sf|github|tag <NEWS>\n";
    exit $exit_code;
}

sub markdownify {
    my ($text) = @_;
    my $out = '';
    my $newpara = 1;

    return '' unless ($text);
    foreach $_ (split /\n/, $text) {
	if (/^\s*[*-]\s/) { $newpara = 1; }
	if (/^$/) { $newpara = 1; }
	if ($newpara && $out) { $out .= "\n"; }
	if (!$newpara) { s/^\s+/ /; }
	$out .= $_;
	$newpara = 0;
    }
    $out .= "\n";
    return $out;
}

sub jaggedness {
    my ($text) = @_;
    my @lengths = map { length($_); } split(/\n/, $text);
    return 0 unless(@lengths);
    my $max = $lengths[0];
    my $min = $max;
    for (my $i = 1; $i < @lengths - 1; $i++) {
	if ($min > $lengths[$i]) { $min = $lengths[$i]; }
	if ($max < $lengths[$i]) { $max = $lengths[$i]; }
    }
    return $max - $min;
}

sub wrap_para {
    my ($para, $width) = @_;

    local $Text::Wrap::columns = $width;
    local $Text::Wrap::huge = 'overflow';
    local $Text::Wrap::unexpand = 0;

    my $indent = '';
    if ($para =~ /^(\s*[*-]\s)/) { $indent = ' ' x length($1); }
    my $wrapped = Text::Wrap::wrap('', $indent, $para);
    my $jags = jaggedness($wrapped);
    if ($jags >= 5) {
	for (my $w = $width - 1; $w > $width - 5; $w--) {
	    $Text::Wrap::columns = $w;
	    my $try = Text::Wrap::wrap('', $indent, $para);
	    my $j = jaggedness($try);
	    if ($j < $jags) {
		$wrapped = $try;
		$jags = $j;
	    }
	}
    }
    return $wrapped;
}

sub wrap_text {
    my ($text, $width) = @_;

    my $para = '';
    my $out = '';
    return $out unless ($text);
    foreach $_ (split /\n/, $text) {
	my $newpara = 0;
	if (/^\s*[*-]\s/) { $newpara = 1; }
	if (/^\s*$/) { $newpara = 1; }
	if ($newpara && $para) {
	    my $indent = '';
	    if ($para =~ /^(\s*[*-]\s)/) { $indent = ' ' x length($1); }
	    $out .= wrap_para($para, $width) . "\n\n";
	    $para = '';
	}
	if (!$newpara) { s/^\s+/ /g; }
	$para .= $_;
    }
    if ($para) {
	my $indent = '';
	if ($para =~ /^(\s*[*-]\s)/) { $indent = ' ' x length($1); }
	$out .= wrap_para($para, $width) . "\n\n";
    }
    return $out;
}

my ($repos, $format);

GetOptions('format=s' => sub {
	       die if ($_[1] !~ /^(?:sf|sourceforge|github|tag)$/i);
	       $format = lc($_[1]);
    },
    'help' => sub { usage(0); }) || usage(1);

my ($in) = @ARGV;
unless ($in) { usage(1); }

if ($in =~ /bcftools/) { $repos = 'bcftools'; }
elsif ($in =~ /samtools/) { $repos = 'samtools'; }
elsif ($in =~ /htslib/) { $repos = 'htslib'; }
else { die "Couldn't get repository name from $in\n"; }

open(my $i, '<', $in) || die "Couldn't open $in $!\n";
my $line = 0;
my $state = 'start';
my $release;
my $date;
my $text;
my $month_re = qr'(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?
|May|June?|July?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?
|Dec(?:ember)?)'x;
my $heading_re = qr"^(?:Noteworthy\schanges\sin\srelease|\#\#\sRelease|Release)\s+
(\d+\.\d+(?:\.\d+)?)\s+
(?:\[[^\]]+\]\s+)?
\(((?:[123]?\d(?:st|nd|rd|th)\s+)?$month_re\s+\d{4})\)$"x;
while (<$i>) {
    $line++;
    if ($state eq 'start') {
	if (/$heading_re/) {
	    $release = $1;
	    $date = $2;
	    $state = /^## Release/ ? 'text' : 'underline';
	    next;
	}
	if ($line > 50) { die "Couldn't find heading in $in\n"; }
    } elsif ($state eq 'underline') {
	if (/^(?:-+|~+|=+)$/) {
	    $state = 'text';
	    next;
	} else {
	    die "Expected underline after heading in $in\n";
	}
    } elsif ($state eq 'text') {
	last if (/$heading_re/);
	next if (!$text && /^\s*$/);
	$text .= $_;
    }
}
close($i) || die "Error reading $in : $!\n";

if ($format =~ /^sf|sourceforge/) {
    print "-" x 78, "\n";
    print "$repos - changes v$release\n";
    print "-" x 78, "\n\n";
    print wrap_text($text, 78);
} elsif ($format eq 'tag') {
    print "$repos release $release:\n\n";
    print wrap_text($text, 70);
} elsif ($format eq 'github') {
    my $do_not_bundle = $repos eq 'htslib' ? '' : " don't bundle HTSlib and";
    print qq[_The **$repos-$release.tar.bz2** download is the full source code release. The “Source code” downloads are generated by GitHub and are incomplete as they$do_not_bundle are missing some generated files._\n];
    print "\n---\n\n";
    print markdownify($text);
}
