#!/usr/local/bin/perl

use strict;
use warnings;

use CPAN::ParseDistribution;
use CPAN::Checksums qw(updatedir);
use File::Find::Rule;
use DBI;
use version;

my $verbose = (@ARGV && shift() eq '-v') ? 1 : 0;

# Configuration for DRC's laptop and for live
use constant BACKPAN => -e '/web/cpxxxan/backpan'
    ? '/web/cpxxxan/backpan'
    : '/Users/david/BackPAN';
use constant CPXXXANROOT => -e '/web/cpxxxan'
    ? '/web/cpxxxan'
    : '.';

my $dbh = DBI->connect('dbi:mysql:database=cpXXXan', 'root', '', { AutoCommit => 0, PrintError => 0 });
my $chkexists = $dbh->prepare('SELECT dist FROM dists WHERE dist=? AND distversion=?');
my $insertdist = $dbh->prepare('INSERT INTO dists (dist, distversion, file, filetimestamp) VALUES (?, ?, ?, FROM_UNIXTIME(?))');
my $insertmod  = $dbh->prepare('INSERT INTO modules (module, modversion, dist, distversion) VALUES (?, ?, ?, ?)');

foreach my $distfile (
  File::Find::Rule
    ->file()
    ->name(qr/\.(tar(\.gz|\.bz2)?|tbz|tgz|zip)$/)
    ->in(BACKPAN.'/authors/id')
) {
    my $dist = eval { CPAN::ParseDistribution->new($distfile, use_tar => '/bin/tar'); };
    next if($@);
    $distfile =~ s!(??{BACKPAN})/authors/id/!!;

    # don't index dev versions
    next if($dist->isdevversion());

    $chkexists->execute($dist->dist(), $dist->distversion());
    next if($chkexists->fetchrow_array());

    # catch, eg, M/MA/MARCEL/-0.01.tar.gz or blahblah-1.0-wibble.tar.gz
    if(!$dist->dist() || $dist->distversion() =~ /[^0-9\.]/) {
        print "SKIP:  $distfile\n" if($verbose);
	next;
    }
    print "FILE: $distfile\n" if($verbose); 

    my %modules = %{$dist->modules()};
    if($insertdist->execute(
        $dist->dist(), $dist->distversion(),
        $distfile,
	(stat("backpan/authors/id/$distfile"))[9]
    )) {
        printf("DIST:   %s: %s\n", $dist->dist(), $dist->distversion())
	    if($verbose);
    } else {
      print $insertdist->errstr."\n";
    }

    foreach(keys %modules) {
	next unless(eval { $modules{$_} ||= 0; 1; });
	if($insertmod->execute($_, $modules{$_}, $dist->dist(), $dist->distversion())) {
            printf("MOD:      %s: %s\n", $_, $modules{$_})
	        if($verbose);
        }
    }
    $dbh->commit();
}
$chkexists->finish();
$dbh->commit();
$dbh->disconnect();

foreach my $dir (File::Find::Rule->directory()->mindepth(3)->in(BACKPAN."/authors/id")) {
    print "Updated $dir/CHECKSUMS\n" if(updatedir($dir) == 2 && $verbose);
}
