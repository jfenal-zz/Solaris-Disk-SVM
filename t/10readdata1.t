# in case Test::More ain't there
# vim: syntax=perl
BEGIN {
    eval { require Test::More; };
    print "1..0\n" and exit if $@;

}

use strict;
use Test::More;
use Data::Dumper;
use lib qw( ./lib ../lib );
use Solaris::Disk::SVM;

use vars qw( %pdevs );

my $tests;
my $datadir="t/data1";
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
is( $svm->{devices}{$_}{type}, "stripe", "$_ is a stripe" ) foreach @stripes;
is( $svm->{devices}{$_}{type}, "concat", "$_ is a concat" ) foreach @concats;
is( $svm->{devices}{$_}{type}, "concat/stripe", "$_ is a concat/stripe" ) foreach @concatstripes;
is( $svm->{devices}{$_}{type}, "hotspare", "$_ is a hotspare" ) foreach @hotspares;
is( $svm->{devices}{$_}{type}, "trans", "$_ is a trans" ) foreach @trans;
is( $svm->{devices}{$_}{type}, "raid5", "$_ is a raid5" ) foreach @raids;

# Coverage

open NULL, "> /dev/null"
    or die "Cannot open /dev/null";
*OUT = *STDOUT;
*STDOUT = *NULL;

# coverage test for show
$svm->showconfig;
$svm->{colour}++;
$svm->showconfig;
$svm->dumpconfig;
$svm->showsp;
$svm->explaindev("d0", "d10");

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

BEGIN {
    %pdevs = (
        d10  => [ 'c1t0d0s0',  'c1t1d0s0' ],
        d11  => [ 'c1t0d0s1',  'c1t1d0s1' ],
        d12  => [ 'c1t0d0s6',  'c1t1d0s6' ],
        d13  => [ 'c1t0d0s5',  'c1t1d0s5' ],
        d15  => [ 'c1t0d0s7',  'c1t1d0s7' ],
        d20  => ['c1t0d0s0'],
        d21  => ['c1t0d0s1'],
        d22  => ['c1t0d0s6'],
        d23  => ['c1t0d0s5'],
        d24  => ['c1t0d0s7'],
        d30  => ['c1t1d0s0'],
        d31  => ['c1t1d0s1'],
        d32  => ['c1t1d0s6'],
        d33  => ['c1t1d0s5'],
        d34  => ['c1t1d0s7'],
        d60  => [ 'c4t10d0s0', 'c3t10d0s0' ],
        d61  => ['c3t10d0s0'],
        d62  => ['c3t10d0s0'],
        d63  => ['c4t10d0s0'],
        d64  => ['c4t10d0s0'],
        d85  => [ 'c4t10d0s0', 'c3t10d0s0' ],
        d86  => ['c3t10d0s0'],
        d87  => ['c3t10d0s0'],
        d88  => ['c4t10d0s0'],
        d89  => ['c4t10d0s0'],
        d130 => [ 'c4t10d0s0', 'c3t10d0s0' ],
        d133 => ['c4t10d0s0'],
        d134 => ['c4t10d0s0'],
        d131 => ['c3t10d0s0'],
        d132 => ['c3t10d0s0'],
        d180 => [ 'c3t12d0s0', 'c4t12d0s0' ],
        d181 => ['c4t12d0s0'],
        d182 => ['c4t12d0s0'],
        d183 => ['c3t12d0s0'],
        d184 => ['c3t12d0s0'],
    );
    $tests += scalar keys %pdevs;
}

foreach my $dev ( sort keys %pdevs ) {
    my @physd = $svm->getphysdevs($dev);
    ok( eq_set( \@physd, $pdevs{$dev} ), "getphysdevs $dev" );
}

do {
#BEGIN { $tests += 2; }
my $cpt=1;
foreach (qw( c0t0d0s0 c2t0d0s0 )) {
    my @mps = $svm->mponslice($_);
    ok(eq_set(\@mps, [ '/' ]), "mponslice ".$cpt++)
}

#BEGIN { $tests += 8; }
foreach ( qw(   c0t1d0s0 c0t2d0s0 c0t3d0s0 c2t1d0s0
                c2t2d0s0 c2t3d0s0 c3t0d0s0 c3t3d0s0 ) ) {
    my @mps = $svm->mponslice($_);
    ok(eq_set(\@mps, [ '/export' ]), "mponslice ".$cpt++)
}

#BEGIN { $tests += 3; }
$cpt=1;
foreach (qw( d10 d11 d12 )) {
    my @mps = $svm->mpondev($_);
    ok(eq_set(\@mps, [ '/' ]), "mpondev ".$cpt++)
}

#BEGIN { $tests += 5; }
foreach ( qw( d1 d2 d50 d51 d52 ) ) {
    my @mps = $svm->mpondev($_);
    ok(eq_set(\@mps, [ '/export' ]), "mpondev ".$cpt++)
}


#BEGIN { $tests += 2; }
$cpt=1;
foreach (qw( c0t0d0 c2t0d0 )) {
    my @mps = $svm->mpondisk($_);
    ok(eq_set(\@mps, [ '/', '/export', '/var', 'swap' ]), "mpondisk ".$cpt++)
}

#BEGIN { $tests += 8; }
foreach ( qw(   c0t1d0 c0t2d0 c0t3d0 c2t1d0
                c2t2d0 c2t3d0 c3t0d0 c3t3d0 ) ) {
    my @mps = $svm->mpondisk($_);
    ok( eq_set( \@mps, ['/export'] ), "mpondisk " . $cpt++ );
}

#devs4mp
#BEGIN { $tests += 5; }
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
#BEGIN { $tests += 5; }
my %mp2disk = (
    '/'       => [qw( c2t0d0s0 c0t0d0s0 )],
    '/export' => [qw( c0t0d0s5 c2t3d0s0 c0t1d0s0 c3t0d0s0 c3t3d0s0 c0t2d0s0
    c2t1d0s0 c2t0d0s5 c2t2d0s0 c0t3d0s0 )],
    '/ext'    => [qw( c3t1d0s0 c3t2d0s0 )],
    'swap'    => [qw( c0t0d0s1 c2t0d0s1 )],
    '/var'    => [qw( c2t0d0s4 c0t0d0s4 c0t0d0s6 c2t0d0s6 )],
);

foreach ( keys %mp2dev ) {
    my @devs = $svm->disks4mp($_);
    ok( eq_set( \@devs, \@{ $mp2disk{$_} } ), "disks4mp $_" );
}

my @d100 = (qw( d91 d92 d93 d94 d95 d96 d97 d98 d99 d201 d202 d203 d204 d205 d206 d207 d208 d208 ) );
#BEGIN { $tests += 18;}
foreach ( @d100 ) {
    my @devs = $svm->getsubdevs( $_ );
    ok( eq_set( \@devs, [ 'd100' ]), "soft part on device");
}

} if 0;


# Coverage

open NULL, "> /dev/null"
    or die "Cannot open /dev/null";
*OUT = *STDOUT;
*STDOUT = *NULL;

# coverage test for show
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

# version
BEGIN { $tests++; }
is($svm->version, 0.02, "Version is ".$svm->version);

#use Data::Dumper; print STDERR Dumper $svm;
