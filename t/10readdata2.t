# in case Test::More ain't there
# vim: syntax=perl
BEGIN {
    eval { require Test::More; };
    print "1..0\n" and exit if $@;

}

use strict;
use Test::More;
use lib qw( ./lib ../lib );
use Solaris::Disk::SVM;

my $tests;
my $datadir="t/data2";
my $metastat = "$datadir/metastat-p.txt";

open METASTAT, $metastat or die "Can not open metastat dump file: $metastat";
my @metastat = <METASTAT>;
close METASTAT;

my ( @mirrors, @softparts, @devices, @stripes, @concats, @concatstripes, @trans,
@raids, @hotspares);

foreach (@metastat) {
    push @hotspares,     $1 if /^(hsp\d+)/;
    push @mirrors,       $1 if /^(d\d+) -m/;
    push @softparts,     $1 if /^(d\d+) -p/;
    push @raids,         $1 if /^(d\d+) -r/;
    push @trans,         $1 if /^(d\d+) -t/;
    push @devices,       $1 if /^(d\d+) 1 1/;
    push @stripes,       $1 if /^(d\d+) (?:[2-9]|\d\d+) 1/;
    push @concats,       $1 if /^(d\d+) 1 (?:[2-9]|\d\d+)/;
    push @concatstripes, $1 if /^(d\d+) (?:[2-9]|\d\d+) (?:[2-9]|\d\d+)/;
}

my $svm = Solaris::Disk::SVM->new( init => 0 );
$svm->{mnttab}->readmtab( mnttab => "$datadir/mnttab.txt" );
$svm->{mnttab}->readstab( swaptab => "$datadir/swaptab.txt" );
$svm->{vtoc}->readvtocdir( $datadir );
$svm->readconfig( metastatp => $metastat );

plan tests => @mirrors + @softparts + @devices + @stripes + @concats +
  @concatstripes + @trans + @raids + @hotspares + $tests;

is( $svm->{devices}{$_}{type}, "mirror", "$_ is a mirror" ) foreach @mirrors;
is( $svm->{devices}{$_}{type}, "softpart", "$_ is a soft partition" ) foreach @softparts;
is( $svm->{devices}{$_}{type}, "device", "$_ is a simple device" ) foreach @devices;
is( $svm->{devices}{$_}{type}, "concat", "$_ is concat" ) foreach @concats;
is( $svm->{devices}{$_}{type}, "stripe", "$_ is stripe" ) foreach @stripes;
is( $svm->{devices}{$_}{type}, "concat+stripe", "$_ is a concat/stripe" ) foreach @concatstripes;
is( $svm->{devices}{$_}{type}, "hotspare", "$_ is a hotspare" ) foreach @hotspares;
is( $svm->{devices}{$_}{type}, "trans", "$_ is a trans" ) foreach @trans;
is( $svm->{devices}{$_}{type}, "raid5", "$_ is a raid5" ) foreach @raids;
# Coverage

open NULL, "> /dev/null"
    or die "Cannot open /dev/null";
*OUT = *STDOUT;
*STDOUT = *NULL;

# coverage test for show

print $svm->size('c2t3d0s0');
print $svm->size('d150');
print $svm->size('poisse');
print $svm->size('d1000');

print $svm->size('d10');     # mirror
print $svm->size('d91');     # soft-part
print $svm->size('d51');     # device
print $svm->size('d151');    # concat
print $svm->size('d152');    # stripe

$svm->showconfig;
$svm->showsp;
$svm->{colour}++;
$svm->showconfig;
$svm->dumpconfig;
$svm->showsp;
$svm->showsp('d100');
$svm->showsp('d1000');
$svm->explaindev("d0", "d10", "d1000");
$svm->explaindev("d1000");

*STDOUT = *OUT;
close NULL;

BEGIN { $tests += 3; }
my $free = $svm->getnextdev;
is( $svm->{devices}{"d$free"}, undef, "Get next dev is not used");
is( $svm->isdevfree($free), 1, "isdevfree is OK with getnextdev");
is( $svm->isdevfree("d$free"), 1, "isdevfree is OK with getnextdev");

my $occpd = $free - 1;
BEGIN { $tests += 3; }
isa_ok( $svm->{devices}{"d$occpd"}, 'HASH', "Get next dev ");
is( $svm->isdevfree($occpd), 0, "isdevfree is still OK with getnextdev");
is( $svm->isdevfree("d$occpd"), 0, "isdevfree is still OK with getnextdev");


BEGIN { $tests += 3; }
my @physd;
@physd = $svm->getphysdevs("d61");
ok(eq_set(\@physd, [ "c3t1d0s0" ]), "getphysdevs d61");

@physd = $svm->getphysdevs( "d60" );
ok(eq_set(\@physd, [ "c3t2d0s0", "c3t1d0s0" ]), "getphysdevs d60" );

@physd = $svm->getphysdevs( "d2" );
ok(eq_set( \@physd, [ qw( c0t1d0s0 c0t2d0s0 c2t1d0s0 c3t0d0s0 ) ]), "getphysdevs d2");


BEGIN { $tests += 2; }
my $cpt=1;
foreach (qw( c0t0d0s0 c2t0d0s0 )) {
    my @mps = $svm->mponslice($_);
    ok(eq_set(\@mps, [ '/' ]), "mponslice ".$cpt++)
}

BEGIN { $tests += 4; }
foreach ( qw(   c0t1d0s0 c0t2d0s0 c2t1d0s0 c3t0d0s0 ) ) {
    my @mps = $svm->mponslice($_);
    ok(eq_set(\@mps, [ '/export' ]), "mponslice ".$cpt++)
}

BEGIN { $tests += 3; }
$cpt=1;
foreach (qw( d10 d11 d12 )) {
    my @mps = $svm->mpondev($_);
    ok(eq_set(\@mps, [ '/' ]), "mpondev ".$cpt++)
}

BEGIN { $tests += 5; }
foreach ( qw( d1 d2 d50 d51 d52 ) ) {
    my @mps = $svm->mpondev($_);
    ok(eq_set(\@mps, [ '/export' ]), "mpondev ".$cpt++)
}


BEGIN { $tests += 2; }
$cpt=1;
foreach (qw( c0t0d0 c2t0d0 )) {
    my @mps = $svm->mpondisk($_);
    ok(eq_set(\@mps, [ '/', '/export', '/var', 'swap' ]), "mpondisk ".$cpt++)
}

BEGIN { $tests += 4; }
foreach ( qw(   c0t1d0 c0t2d0 c2t1d0 c3t0d0 ) ) {
    my @mps = $svm->mpondisk($_);
    ok( eq_set( \@mps, ['/export'] ), "mpondisk " . $cpt++ );
}

#devs4mp
BEGIN { $tests += 5; }
my %mp2dev = (
    '/'       => [qw( d10 d12 d11 )],
    '/export' => [qw( d1 d2 d50 d51 d52)],
    '/ext'    => [qw( d60 d61 d62 )],
    'swap'    => [qw( d30 d31 d32 )],
    '/var'    => [qw( d3 d20 d21 d22 d40 d41 d42 )],
);

foreach ( keys %mp2dev ) {
    my @devs = $svm->devs4mp($_);
    ok( eq_set( \@devs, \@{ $mp2dev{$_} } ), "devs4mp $_" );
}

#disks4mp
BEGIN { $tests += 5; }
my %mp2disk = (
    '/'       => [qw( c2t0d0s0 c0t0d0s0  )],
    '/export' => [qw( c2t0d0s5 c0t0d0s5 c0t1d0s0 c0t2d0s0 c2t1d0s0 c3t0d0s0 )],
    '/ext'    => [qw( c3t1d0s0 c3t2d0s0 )],
    'swap'    => [qw( c0t0d0s1 c2t0d0s1 )],
    '/var'    => [qw( c2t0d0s4 c0t0d0s4 c0t0d0s6 c2t0d0s6 )],
);

foreach ( keys %mp2dev ) {
    my @devs = $svm->disks4mp($_);
    ok( eq_set( \@devs, \@{ $mp2disk{$_} } ), "disks4mp $_" );
}

my @d100 = (qw( d91 d92 d93 d94 d95 d96 d97 d98 d99 d201 d202 d203 d204 d205 d206 d207 d208 d208 ) );
BEGIN { $tests += 18;}
foreach ( @d100 ) {
    my @devs = $svm->getsubdevs( $_ );
    ok( eq_set( \@devs, [ 'd100' ]), "soft part on device");
}


# version
BEGIN { $tests++; }
is($svm->version, 0.02, "Version is ".$svm->version);

#use Data::Dumper; print STDERR Dumper $svm;
