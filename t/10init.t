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

plan tests => 4;

my $svm = Solaris::Disk::SVM->new( init => 1, sourcedir => 't/data1' );
isa_ok($svm, 'Solaris::Disk::SVM', 'new init + sourcedir');

$svm = undef;

$svm = Solaris::Disk::SVM->new( sourcedir => 't/data1' );
isa_ok($svm, 'Solaris::Disk::SVM', "new sourcedir");

$svm = undef;
$svm = Solaris::Disk::SVM->new;
isa_ok($svm, 'Solaris::Disk::SVM', "new no arg");

$svm = undef;
$svm = Solaris::Disk::SVM->new(init => 1);
isa_ok($svm, 'Solaris::Disk::SVM', "new sourcedir init =>1");

