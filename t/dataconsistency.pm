package dataconsistency;

# vim: syntax=perl

use strict;
use warnings;
use Test::More;
use lib qw( ./lib ../lib );
use Solaris::Disk::SVM;

BEGIN {
    use Exporter ();
    our ( @ISA, @EXPORT );
    @ISA    = qw(Exporter);
    @EXPORT = qw(&checksvmcons);
}

sub checksvmcons ($) {
    my $datadir = shift;

    my $metastat = "$datadir/metastat-p.txt";

    my %notspurious = (
        'Metastat'        => qr/^(?:d\d+|hsp\d+)$/,
        'SPSize'          => qr/^d\d+$/,
        'SPOffset'        => qr/^d\d+$/,
        'Partitions'      => qr/^c\d+t\d+d\d+s\d+$/,
        'dev2mp'          => qr/^(?:c\d+t\d+d\d+s\d+|d\d+)$/,
        'LeafPhysDevices' => qr/^(?:c\d+t\d+d\d+s\d+|d\d+)$/,
        'SubElements'     => qr/^(?:c\d+t\d+d\d+s\d+|d\d+|hsp\d+)$/,
        'pdev2mp'         => qr/^(?:c\d+t\d+d\d+s\d+)$/,
        'SPContains'      => qr/^(?:c\d+t\d+d\d+s\d+|d\d+)$/,
        'objtype'         =>
          qr/(?:mirror|softpart|device|stripe|concat|concat\+stripe|hotspare|raid5|trans)/,
        'PhysDevices4Dev' => qr/^d\d+$/,
    );

    my @shouldbe = (
        'LeafPhysDevices', 'Metastat',
        'Partitions',      'PhysDevices4Dev',
        'SPContains',      'SPOffset',
        'SPSize',          'SubElements',
        'dev2mp',          'devices',
        'metastatSource',  'mnttab',
        'mp2dev',          'objtype',
        'pdev2mp',         'vtoc'
    );

    my $svm = Solaris::Disk::SVM->new( init => 0 );
    $svm->{mnttab}->readmtab( mnttab => "$datadir/mnttab.txt" );
    $svm->{mnttab}->readstab( swaptab => "$datadir/swaptab.txt" );
    $svm->{vtoc}->readvtocdir($datadir);
    $svm->readconfig( metastatp => $metastat );

    my $numtests =
      1 + ( scalar( map { keys %{ $svm->{$_} } } keys %notspurious ) ) +
      scalar( keys( %{ $svm->{devices} } ) );

    $numtests -= scalar( keys( %{ $svm->{objtype}{hotspare} } ) )
      if defined $svm->{objtype}{hotspare};

    plan tests => $numtests;

    # Data structure consistency
    my @firstlevel = sort keys %{$svm};

    is_deeply( \@firstlevel, \@shouldbe, "First level hash keys" );

    foreach my $key ( keys %notspurious ) {
        foreach my $content ( keys %{ $svm->{$key} } ) {
            like( $content, $notspurious{$key},
                "svm->{$key} is like $notspurious{$key}" );
        }
    }
    foreach ( sort keys %{ $svm->{devices} } ) {
        my $devtype = $svm->{devices}{$_}{type};
        next if $devtype eq 'hotspare';
        cmp_ok( $svm->size($_), '>', 0, "$_ (" . $devtype . ") size not zero" );
    }
}

1;
