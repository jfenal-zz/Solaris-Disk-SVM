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

my $svm = Solaris::Disk::SVM->new( some => 'garbage', init => 0 );
$svm->{mnttab}->readmtab( mnttab => "$datadir/mnttab.txt" );
$svm->{mnttab}->readstab( swaptab => "$datadir/swaptab.txt" );
$svm->{vtoc}->readvtocdir( $datadir );
$svm->readconfig( metastatp => $metastat );

plan tests => 1;

isa_ok($svm, "Solaris::Disk::SVM", "Still get an object with garbage options");
