package Solaris::Disk::SVM;

use strict;
use warnings;
use Carp;
use Solaris::Disk::VTOC;
use Solaris::Disk::Mnttab;
use Term::ANSIColor;

my $VERSION;
$VERSION = 0.02;

=head1 NAME

Solaris::Disk::SVM - Read, explore and manipulate SVM disk configurations

=head1 SYNOPSIS

  my $svm = Solaris::Disk::SVM->new( init => 1 );
  $svm->dumpconfig();

  my $svm = Solaris::Disk::SVM->new( init => 1, sourcedir => 't/data' );
  $svm->dumpconfig();

  my $svm = Solaris::Disk::SVM->new( init => 0 );

  $svm->{mnttab}->readmtab( mnttab  => 't/data/mnttab.txt' );
  $svm->{mnttab}->readstab( swaptab  => 't/data/swaptab.txt' );
  $svm->{vtoc}->readvtocdir( 't/data' );

  $svm->readconfig( metastatp => 't/data/metastat-p.txt' );

=head1 DESCRIPTION

The Solaris::Disk::SVM object allows to read (all) the necessary information to
restitute this information in a computer B<and> human readable manner.

Its main purpose is to provide support to the svm(1) script included in the
Solaris::Disk::SVM distribution.

=cut

# %Metastat :     $Device{nom du device} = description texte
# %LeafPhysDevices : $LeafPhysDevices{nom du device} = liste des devices physiques
#                                              directement sous la structure
# %SPContains :  $SPContains{nom du device} = liste des devices sur une SP
# %SPDev :       $SPDev{nom du device} = nom du device où est taillée
#                                        la soft partition
# %SPOffset :    $SPOffset{nom du device} = offset
# %SPSize :      $SPSize{nom du device} = taille
# %SubElements : $SubElements{nom du device} = liste des sous-devices d*
# %SoftPartitions:

#use vars qw(
#  %Metastat %LeafPhysDevices %SPOffset %SPSize %SPDev %SPContains
#  %DevType $self->{debug} %SubElements
#  %PhysDevices4Dev %Partitions %VTOC
#  $self->{colour}
#);

=head1 METHODS

=head2 C<new>

The C<new> method returns a new C<Solaris::Disk::SVM> object.

No initialisation nor information read:

  $svm =  Solaris::Disk::SVM->new();

Initialise and read tables, from optional sources: 

    $svm = Solaris::Disk::SVM->new(
        init => 1,
        metastatp => 'metastat -p |',
      );

If running on different OS than Solaris, or on a different host than the target
one, you may need to specify other data sources such as the one for
C<Solaris::Disk::Mnttab> and C<Solaris::Disk::VTOC>.

=cut

sub new {
    my ( $class, @args ) = @_;
#    $class = ref($class) || $class;

    my $self = {};

    my %parms;
    my $i = 0;
    my $re = join "|", qw( metastatp init sourcedir );
    $re = qr/^(?:$re)$/;
    while ( $i < @args ) {
        if ( $args[$i] =~ $re ) {
            my ( $k, $v ) = splice( @args, $i, 2 );
            $parms{$k} = $v;
        }
        else {
            $i++;
        }
    }

    # shouldn't be anything left in # @args
    warn "Unknown parameter(s): @args" if @args;

    # Create the vtoc object, but do initialize it.
    # In case of file based source, it would be initialized explicitely, and
    # further calls to C<readvtoc> by C<readconfig> will shortly return as disk
    # partition already loaded by hand. So init could not be 1 in this case, and
    # readconfig should also be explicitely called.
    $self->{vtoc}   = Solaris::Disk::VTOC->new( init   => 0 );
    $self->{mnttab} = Solaris::Disk::Mnttab->new( init => 0 );
    bless $self, $class;

    if (defined $parms{sourcedir}) {
        $parms{metastatp} = $parms{sourcedir}. "/metastat-p.txt";
        $self->{mnttab}->readmtab( mnttab => $parms{sourcedir}."/mnttab.txt" );
        $self->{mnttab}->readstab( swaptab => $parms{sourcedir}. "/swaptab.txt" );
        $self->{vtoc}->readvtocdir( $parms{sourcedir} );
    }

    if ( defined( $parms{init} ) && $parms{init} == 1 ) {
        $self->readconfig(
            defined( $parms{metastatp} )
            ? ( metastatp => $parms{metastatp} )
            : () ) ;
    }

    $self;
}

=head2 C<sdscreateobject>

  $sds->createobject( $dev, $desc);
  $sds->createobject( 'd101', '1 1 d102');
  $sds->createobject( 'd100', '-m d101 d103');

We pass a new object description to C<sdscreateobject> to add it to the memory
configuration, in order to propagate sub-objects to the whole configuration.

=cut

sub sdscreateobject($$) {
    my ( $self, $dev, $desc ) = @_;
    my @desc;

    if ( $dev =~ m/^d\d+$/ ) {
#        print STDERR "Reading $dev\n";
        for ($desc) {

            # A soft partition
            /^\-p.*/ and do {
                @desc = split /\s+/, $desc;
                my %spdesc;
                while ( my $opt = shift @desc ) {
                    if ( $opt eq '-p' ) {
                        my $spd = shift @desc;
                        $spdesc{device} = $spd
                          if defined $spd;
                    }
                    if ( $opt eq '-o' ) {
                        my $offset = shift @desc;
                        push @{ $spdesc{offsets} }, $offset
                          if defined $offset;
                    }
                    if ( $opt eq '-b' ) {
                        my $blocks = shift @desc;
                        push @{ $spdesc{sizes} }, $blocks
                          if defined $blocks;
                    }
                }
                if (
                    !(
                           defined( $spdesc{sizes} )
                        && defined( $spdesc{offsets} )
#                        && defined( $spdesc{device} )
                    )
                  )
                {
                    warn "Incomplete soft partition definition for $dev";
                    delete $self->{Metastat}{$dev};
                    return;
                }
                
                $self->{devices}{$dev}{type} = "softpart";

                $self->{objtype}{ $self->{devices}{$dev}{type} }{$dev}{device} =
                  $spdesc{device};

                if ( $spdesc{device} =~ /c\d+t\d+d\d+s\d+/ ) {
                    $self->{LeafPhysDevices}{$dev}{$spdesc{device}}++;
                    $self->{Partitions}{ $spdesc{device} }{use}++;
                    $self->{PhysDevices4Dev}{$dev}{$spdesc{device}}++;
                } else {
                    push @{ $self->{SubElements}{$dev} }, $spdesc{device};
                }

                $self->{SPSize}{$dev} = 0;
                foreach my $i ( 0 .. scalar(@{$spdesc{offsets}})-1 ) {
                    my $size = @{ $spdesc{sizes} }[$i];
                    push @{ $self->{SPContains}{ $spdesc{device} } },
                      [
                        @{ $spdesc{offsets} }[$i],
                        @{ $spdesc{sizes} }[$i],
                        $dev
                      ];
                    $self->{SPSize}{$dev} += @{ $spdesc{sizes} }[$i];
                }
                $self->{SPOffset}{$dev} = $spdesc{offsets};

                $self->{devices}{$dev}{explanation} =
                    "$dev is a soft partition (dev="
                  . join( " ", keys %{$self->{LeafPhysDevices}{$dev}} )
                  . ", size="
                  . $self->{SPSize}{$dev}
                  . ", offset={"
                  . join( ', ', @{ $self->{SPOffset}{$dev} } ) . "}) ";


                last;
            };

            # RAID 5
            /^\-r.*/ and do {
                @desc = split /\s+/, $desc;
                shift @desc;    # pass by the -r
                my $columns;
                my @elements;

                while ( my $el = shift @desc ) {
                    for ($el) {
                        /^d\d+/ and do {
                            push @{ $self->{SubElements}{$dev} }, $el;
                            push @elements, $el;
                            $columns++;
                            last;
                        };
                        /^c\d+t\d+d\d+s\d+/ and do {
                            $self->{Partitions}{$el}{'use'}++;
                            $self->{LeafPhysDevices}{$dev}{$el}++;
                            $self->{PhysDevices4Dev}{$dev}{$el}++;
                            push @elements, $el;
                            $columns++;
                            last;
                        };
                        /^\-k$/ and do {
                            $self->{devices}{$dev}{kflag}++;
                            last;
                        };
                        /^\-i$/ and do {
                            $self->{devices}{$dev}{iflag} = shift @desc;
                            last;
                        };
                        /^\-o$/ and do {
                            $self->{devices}{$dev}{oflag} = shift @desc;
                            last;
                        };
                    }
                }
                $self->{devices}{$dev}{type} = 'raid5';

                $self->{objtype}{raid5}{$dev}{columns} = $columns;
                $self->{devices}{$dev}{explanation} =
                  "$dev is a raid5 with $columns columns ("
                  . join( " ", @elements ) . ")";

                last;
            };

            # Trans (journalised device)
            /^\-t.*/ and do {
                @desc = split /\s+/, $desc;
                shift;    # pass by the -t
                foreach (@desc) {
                    if (/d\d+/) {
                        push @{ $self->{SubElements}{$dev} }, $_;
                    }
                }
                $self->{devices}{$dev}{type} = 'trans';

                $self->{objtype}{ $self->{devices}{$dev}{type} }{$dev}
                  {columns} = 0 + @{ $self->{SubElements}{$dev} };
                $self->{devices}{$dev}{explanation} =
                  "$dev is a trans ("
                  . join( " ", @{ $self->{SubElements}{$dev} } ) . ")";

                last;
            };

            # mirror
            /^\-m.*/ and do {

                #  print "$dev is a mirror ($desc)\n";
                @desc = split /\s+/, $desc;
                shift;    # pass by the -m
                foreach (@desc) {
                    if (/d\d+/) {
                        push @{ $self->{SubElements}{$dev} }, $_;
                    }
                }
                $self->{devices}{$dev}{type}        = 'mirror';
                $self->{devices}{$dev}{explanation} =
                  "$dev is a mirror ("
                  . join( " ", @{ $self->{SubElements}{$dev} } ) . ")";

                $self->{objtype}{ $self->{devices}{$dev}{type} }{$dev}{sides} =
                  scalar @{ $self->{SubElements}{$dev} };
                  # print STDERR "WARNING : " . $self->{devices}{$dev}{type} . " $dev has only one side\n" if ( @{ $self->{SubElements}{$dev} } == 1 );
                last;
            };

            # device / concat / stripe
            /^[0-9]+.*/ and do {

                #  print "$dev is a concat stripe ($desc)\n";
                @desc = split /\s+/, $desc;
                my $nstripe   = shift @desc;  # nombre de colonnes du stripe
                my $cstripe   = 0;            # nombre de concat dans la colonne
                my $maxconcat = 0;            # impossible
                                              #
                foreach my $i ( 1 .. $nstripe ) {
                    $cstripe   = shift @desc;
                    $maxconcat = $cstripe
                      if ( $maxconcat < $cstripe );    # max allégé
                    foreach my $j ( 1 .. $cstripe ) {
                        my $el = shift @desc;
                        
                        for ($el) {
                            /^d\d+$/ and do {
                                # TODO: check if $el is a softpart
                                #if ( defined($self->{devices}{$el}{type}) &&
                                #    $self->{devices}{$el}{type} ne 'softpart') {
                                #    warn "$el is already a device, not a soft-partition"
                                #}
                                push @{ $self->{SubElements}{$dev} }, $el;
                                last;
                            };
                            /^c\d+t\d+d\d+s\d+$/ and do {
                                $self->{LeafPhysDevices}{$dev}{$el}++;
                                $self->{PhysDevices4Dev}{$dev}{$el}++;

                                #   push @{ $self->{SubElements}{$dev} }, $el;
                                $self->{Partitions}{$el}{'use'}++;

                                #              push @{$SubElements{$dev}}, $el;
                                last;
                            };
                        }
                    }
                }

                my $el = shift @desc;
                if (defined $el and $el eq '-i' ) {
                    my $fl = shift @desc;
                    $self->{devices}{$dev}{iflag} = $fl
                      if defined $fl;
                }

                if ( $nstripe == 1 && $maxconcat == 1 ) {
                    $self->{devices}{$dev}{type} = "device";
                }
                if ( $nstripe > 1 && $maxconcat == 1 ) {
                    $self->{devices}{$dev}{type} = "stripe";
                }
                if ( $nstripe == 1 && $maxconcat > 1 ) {
                    $self->{devices}{$dev}{type} = "concat";
                }
                if ( $nstripe > 1 && $maxconcat > 1 ) {
                    $self->{devices}{$dev}{type} = "concat+stripe";
                }
                $self->{objtype}{ $self->{devices}{$dev}{type} }{$dev}++;
                $self->{devices}{$dev}{explanation} =
                  "$dev is a " . $self->{devices}{$dev}{type};
                $self->{devices}{$dev}{explanation} .=
                  " (" . join( " ", @{ $self->{SubElements}{$dev} } ) . ")"
                  if defined $self->{SubElements}{$dev};
                last;
            };
        }
    }

    # hot-spare
    if ( $dev =~ m/^hsp\d+/ ) {
        my @desc = split /\s+/, $desc;

        $self->{devices}{$dev}{type} = 'hotspare';
        if (@desc) {
            print "$dev\n";
            $self->{SubElements}{$dev} = @desc;
            $self->{devices}{$dev}{explanation} =
              "$dev is a hotspare ("
              . join( " ", @desc) . ")";
            $self->{objtype}{hotspare}{$dev}{disks} = scalar @desc;
        }
        else {
            $self->{SubElements}{$dev} = ();
            $self->{objtype}{hotspare}{$dev}{disks} = 0;
            $self->{devices}{$dev}{explanation} =
              "$dev is a hotspare without any disk";

        }
    }
}

=head2 C<readconfig>

  $svm->readconfig( metastatp => 'metastatp.txt' );

C<readconfig> reads a data source in 'metastat -p' format, and creates
configuration from it calling sdscreateobject and propagating device
dependencies.

The C<metastatp> named argument can provide a file source to use instead of
'F<metastat -p |>'.

Returns non 0 on error.

=cut

sub readconfig(@) {
    my ( $self, @args ) = @_;
    my $dev;     # le device courant
    my $desc;    # la description courante en texte
    my @desc;    # la description courante en liste
    my %desc;    # la description courante en hash

    my %parms;
    my $i = 0;
    my $re = join "|", qw( metastatp );
    $re = qr/^(?:$re)$/;
    while ( $i < @args ) {
        if ( $args[$i] =~ $re ) {
            my ( $k, $v ) = splice( @args, $i, 2 );
            $parms{$k} = $v;
        }
        else {
            $i++;
        }
    }

    # shouldn't be anything left in @args
    warn "Unknown parameter(s): @args"
      if @args;

    $self->{metastatSource} = "metastat -p |";  # the default source... maybe
                                                # should we specify full path...

    $self->{metastatSource} = $parms{metastatp}
      if defined $parms{metastatp};

    if (! open MS, $self->{metastatSource}) {
        warn "Cannot open metastat source '$self->{metastatSource}'";
        return -1;
    }

    while (<MS>) {
        next if m/^#/;
        while ( $_ =~ /.*\\\n/ ) {
            chomp;    # chomp terminal \n
            chop;     # chop the terminal \\ for next line
            $_ .= readline(*MS);    # concat next line from MS
        }
        ( $dev, @desc ) = split;

        next if not defined($dev);  # empty line

        if ( defined $self->{Metastat}{$dev} ) {
            warn "$dev is already defined, and one more definition is given";
        }
        else {
            $self->{Metastat}{$dev} = join " ", @desc;
            $self->sdscreateobject( $dev, $self->{Metastat}{$dev} );
        }
    }
    if (! close MS) {
        warn "lost metastat source '$self->{metastatSource}'";
        return -1;
    }

    # On a maintenant un hash %Metastat qui contient la config brute
#    while ( ( $dev, $desc ) = each %{ $self->{Metastat} } ) { $self->sdscreateobject( $dev, $desc ); }

    #
    # Passe pour assigner les physical à tt le monde
    #
    foreach $dev ( keys %{ $self->{Metastat} } ) {
        foreach my $sdev ( $self->getsubdevs($dev) ) {
            if ( defined( %{ $self->{LeafPhysDevices}{$sdev} } ) ) {
                foreach my $i ( keys %{ $self->{LeafPhysDevices}{$sdev} } ) {
                    $self->{PhysDevices4Dev}{$dev}{$i}++;
                }
            }
        }
   }

    # FIXME : test avant de lancer le readvtoc
    #
    # Recuperation des informations des partitions
    #
    foreach $dev ( keys %{ $self->{Partitions} } ) {
#        if ( $dev =~ m/c\d+t\d+d\d+/ ) {
            $self->{vtoc}->readvtoc( device => $dev );
            $self->{Partitions}{$dev}{size} = $self->{vtoc}->size($dev);
#        }
    }
    foreach $dev ( keys %{ $self->{LeafPhysDevices} } ) {
        foreach my $part (keys %{$self->{LeafPhysDevices}{$dev}}) {
            $self->{vtoc}->readvtoc( device => $part );
        }
    }

    # A priori, les informations sur les partitions sont maintenant complètes,
    # que ce soit directement par le dernier code, ou par le biais d'une lecture
    # manuelle entre l'init et le readconfig.
    # On peut donc faire les propagations dev2mp, mp2dev, mp2pdev, pdev2mp

    foreach $dev ( keys %{ $self->{mnttab}->{dev2mp} } ) {
        next if $dev !~ m/(?:d\d+|c\d+t\d+d\d+(?:s\d+)*)/;
        my $mnt = $self->{mnttab}->{dev2mp}{$dev};

        # Copie dans l'objet svm
        $self->{dev2mp}{$dev}{$mnt}++;
        $self->{mp2dev}{$mnt} = $dev;
        foreach my $subdev ( $self->getsubdevs($dev) ) {
            $self->{dev2mp}{$subdev}{$mnt}++;
        }
        foreach my $pdev ( keys %{ $self->{PhysDevices4Dev}{$dev} } ) {
            #           print STDERR "phys dev $pdev\n";
            $self->{pdev2mp}{$pdev}{$mnt}++;
        }
    }

    $self;
}

=head2 C<size>

 $svm->size( $device );

C<size> returns the size (in blocks) of C<$device>.

=cut

sub size($$) {
    my ( $self, $dev ) = @_;
    my $size = 0;
    my $disk;
    my $pn;

    if ( $dev =~ m/(c\d+t\d+d\d+)s(\d+)/ ) {
        ( $disk, $pn ) = ( $1, 'slice' . $2 );
        $size = $self->{vtoc}{$disk}{$pn}{count};
    }
    elsif ( $dev =~ m/d\d+/ ) {
        if ( defined( $self->{SPSize}{$dev} ) ) {
            $size = $self->{SPSize}{$dev};
        }
        elsif ( defined($self->{devices}{$dev}) && scalar @{ $self->{SubElements}{$dev} } ) {
            my $Msize = 0;
            my $msize = 1 << 31;    # some maximum value
            foreach my $se ( @{ $self->{SubElements}{$dev} } ) {
                my $s = $self->size($se);
                $Msize = $s if $s > $Msize;
                $msize = $s if $s < $msize;
                $size += $s;
            }
            if ( $self->{devices}{$dev}{type} eq 'trans' ) {
                $size = $Msize;    # le maxima
            }
            if ( $self->{devices}{$dev}{type} eq 'mirror' ) {
                $size = $msize;    # le minima
            }
            if ( $self->{devices}{$dev}{type} eq 'raid5' ) {
                $size = $msize * ( scalar(@{ $self->{SubElements}{$dev} }) - 1 );
            }
        }
        elsif ( scalar keys %{$self->{LeafPhysDevices}{$dev}} ) {
            my $msize = 1 << 31;    # some maximum value
            foreach my $se ( keys %{ $self->{LeafPhysDevices}{$dev} } ) {
                my $s = $self->{vtoc}->size($se);
                $size += $s;
                $msize = $s if $s < $msize;
            }
#            if ( $self->{devices}{$dev}{type} eq 'mirror' ) { $size = $msize;    # le minima }
            if ( $self->{devices}{$dev}{type} eq 'raid5' ) {
                $size = $msize * ( scalar(keys %{ $self->{LeafPhysDevices}{$dev} }) - 1 );
            }
        }

    }

    return $size;
}

=head2 C<showconfig>

 $svm->showconfig(); # no argument

C<showconfig> dumps in a (almost) human readable manner the configuration.

=cut

sub showconfig($) {
    my ($self) = @_;

    my (@devs, @hsps);

    foreach (keys %{ $self->{devices} } ) {
            push( @devs, $1) if m/^d(\d+)/;
            push( @hsps, $1) if m/^hsp(\d+)/;
    }

    print "SVM Configuration:\n";
    foreach ( sort { $a <=> $b } @devs ) {
        my $dev = "d$_";
        my $devsize = $self->size($dev) >> 11;
        print "$dev ("
          . $self->{devices}{$dev}{type} . "): "
          . $self->{devices}{$dev}{explanation}
          . " [$devsize Mo]\n";
    }

    foreach ( sort { $a <=> $b } @hsps ) {
        my $dev = "hsp$_";
        print "$dev ("
          . $self->{devices}{$dev}{type} . "): "
          . $self->{devices}{$dev}{explanation}
          . "\n";
    }
}

=head2 C<dumpconfig>

C<dumpconfig> will, when implemented, dump the loaded configuration in the
"metastat -p" format.

=cut

sub dumpconfig { 1; }


=head2 C<showsp>

  $svm->showsp();
  $svm->showsp( "c4t10d0s0" );  # for softparts on disk slice
  $svm->showsp( "d100" );       # for softparts on devices

C<showsp> prints the list of the given soft-partition(s) container.

=cut

sub showsp(@) {
    my ( $self, @devs ) = @_;
#    sub _sortbyoffset { $a->[0] <=> $b->[0] }

    my ( $reset, $red, $green );
    if ( $self->{colour} ) {
        $reset = color('reset');
        $red   = color('red');
        $green = color('green');
    } else {
        $reset = $red  = $green = "";
    }
    

    @devs = keys %{ $self->{SPContains} } if @devs == 0;
    foreach my $dev ( sort @devs ) {
        my $offset       = 1;
        my $precendblock = -1;
        if ( exists( $self->{SPContains}{$dev} ) ) {
            print "\n---- Contenu de la soft partition $dev ----\n";
            print
"Partition | Device |     Offset |        End |       Size            | Mountpoint\n";
            print
"----------+--------+------------+------------+-----------------------------------\n";
            my $tsize = 0;
            foreach
              my $list ( sort { $a->[0] <=> $b->[0] } @{ $self->{SPContains}{$dev} } )
            {
                my $offset   = $list->[0];
                my $size     = $list->[1];
                my $endblock = $offset + $size - 1;

                if ( ( $offset - $precendblock ) > 2 ) {
                    print $green;
                    printf(
                        "%-9s | *FREE* | %10d | %10d | %10d (%5d Mo) | free\n",
                        $dev,
                        $precendblock + 2,
                        $offset - 2,
                        $offset - $precendblock - 3,
                        ( $offset - $precendblock - 3 ) >> 11,
                    );
                    print $reset;
                }

                printf(
                    "%-9s |  %5s | %10d | %10d | %10d (%5d Mo) | %s\n",
                    $dev,
                    $list->[2],
                    $offset,
                    $endblock,
                    $size,
                    $size >> 11,
                    defined $self->{dev2mp}{ $list->[2] }
                    ? join( " ", keys %{ $self->{dev2mp}{ $list->[2] } } )
                    : ''
                );
                $tsize += $list->[1];
                $precendblock = $endblock;
            }

            if ( $dev =~ m!(c\d+t\d+d\d+)s(\d)! ) {
                my ( $disk, $pn );
                ( $disk, $pn ) = ( $1, 'slice' . $2 );
                if (
                    (
                        my $free =
                        $self->{vtoc}->{$disk}{$pn}{count} -
                        ( $precendblock + 2 )
                    ) > 0
                  )
                {
                    print $green;
                    printf(
                        "%-9s | *FREE* | %10d | %10d | %10d (%5d Mo) | free\n",
                        $dev,
                        $precendblock + 2,
                        $self->{vtoc}->{$disk}{$pn}{count},
                        $free, $free >> 11,
                    );
                    print $reset;
                }
                else {
                    print $red;
                    printf( "%-9s | No more free space...\n", $dev );
                    print $reset;
                }
            }
            else {
                my $devsize = $self->size($dev);
                if ( ( my $free = $devsize - $precendblock - 1 ) > 0 ) {
                    print $green;
                    printf(
                        "%-9s | *FREE* | %10d | %10d | %10d (%5d Mo) | free\n",
                        $dev, $precendblock + 2,
                        $devsize, $free, $free >> 11,
                    );
                    print $reset;
                }
                else {
                    warn "More devices defined than free space available: should not happen";
                }
            }
            print
"----------+--------+------------+------------+-----------------------------------\n";
            printf(
"Total space used   |            |            | %10d (%5d Mo)\n",
                $tsize, $tsize >> 11 );
        }
    }
}

=head2 C<explaindev>

  $svm->explaindev( 'd1', 'd2' );

C<explaindev> prints an explaination about devices asked for.
Multiple device names can be passed in arguments as a list.

=cut 

sub explaindev(@) {
    my ( $self, @devs ) = @_;

    foreach my $dev (@devs) {
        next if not defined $self->{devices}{$dev};
        my $devsize = $self->size($dev) >> 11;
        print $self->{devices}{$dev}{explanation}
          . ". It is $devsize MB large\n";
    }
}

=head2 C<getnextdev>

  my $nextdevid = 'd' . $svm->getnexdev;

C<getnextdev> takes no arguments, and returns the first free device
number beyond the last one defined.

Used to find what number to give to a new device.

=cut

sub getnextdev($) {
    my ($self) = @_;

    # search among devices only
    my @devs = sort { $a <=> $b } map { $1 if m/^d(\d+)/ } keys %{ $self->{devices} };

    $devs[-1] + 1;
}

=head2 C<isdevfree>

  my $isfree{$dev} = $svm->isdevfree( $dev );

C<isdevfree> take a device name (C</^d\d$/>) or a device number in argument
and return 0 if the device is already defined, 1 if the device is not
defined.

=cut

sub isdevfree($$) {
    my ( $self, $dev ) = @_;

    $dev = "d$dev" if ( $dev =~ /^\d+$/ );
#    if ( defined $self->{Metastat}{$dev} ) { return 0; } else { return 1; }
    defined $self->{Metastat}{$dev} ? 0 : 1;
}

# $1 = dev_id
# $2 = axis
# $3 = size
# [$4] = mountpoint
# to make a mirror, we have to :
# - make a soft part
# - make concat/dev containing the soft part
# - use two of these in a mirror
# axis : 0..number of disks
# side : 0..1
# d40+5*n : mirror device
# d40+5*n + (side*2) + 1 : concat/stripe device lying on +2
# d40+5*n + (side*2) + 2 : soft partition
# make both soft parts
#sub mkmirror
#{
#    my $dev_id     = shift;
#    my $axis       = shift;
#    my $size       = shift;
#    my $mountpoint = shift;    # as forcement renseigne
#    if ( defined($mountpoint) && $mountpoint !~ /^\/.*/ ) {
#        undef $mountpoint;
#    }
#
#    foreach ( 0 .. 4 ) {
#        my $testid = $dev_id + $_;
#        if ( !isdevfree($testid) ) {
#            print "#!! WARNING : device d$testid not free, aborting\n";
#            exit 1;
#        }
#    }
#
#    my @concats;
#    my $i;
#    foreach $i ( 0 .. 1 ) {    # pans de mirroir
#        my $concat   = $dev_id + $i * 2 + 1;
#        my $softpart = $dev_id + $i * 2 + 2;
#        print "#### concat $i = $concat"     if $self->{debug};
#        print "#### softpart $i = $softpart" if $self->{debug};
#
#        # softpart
#        my @Ctrls = keys %Axis;
#        my @Disks = @{ $Axis{ $Ctrls[$i] } };
#        print "metainit d$softpart -p c$Ctrls[$i]t$Disks[$axis]d0s0 $size\n";
#
#        # concat on soft part
#        print "metainit d$concat 1 1 d$softpart\n";
#        $concats[$i] = $concat;
#    }
#
#    # mirror itself
#    print "metainit d$dev_id -m d$concats[0]\n";
#    print "#metattach d$dev_id  d$concats[1]\n";
#
#    print "newfs /dev/md/dsk/d$dev_id\n";
#    if ( defined($mountpoint) ) {
#        print "mkdir $mountpoint\n";
#        print "mount /dev/md/dsk/d$dev_id $mountpoint\n";
#    }
#}

=head2 C<getsubdevs>

    @sdevs = $svm->getsubdevs( 'd10' );
    @sdevs = $svm->getsubdevs( 'd10', 'd20' );

C<getsubdevs> returns the list of devices underlying those passed as
argument(s). Only one level deep.

=cut

sub getsubdevs {
    my ( $self, @devs ) = @_;
    my @subdevs;

    foreach my $dev (@devs) {
        if ( defined( @{ $self->{SubElements}{$dev} } ) ) {
            @subdevs = @{ $self->{SubElements}{$dev} };
            foreach my $cdev (@subdevs) {
                push @subdevs, $self->getsubdevs($cdev);
#                  if ($cdev =~ /d\d+/);
            }
        }
    }

    @subdevs;
}

=head2 C<getphysdevs>

    @pdevs = $svm->getphysdevs( 'd10' );
    @pdevs = $svm->getphysdevs( 'd10', 'd20' );

C<getphysdevs> returns the list of physical devices underlying those
passed as argument(s).

=cut

sub getphysdevs(@) {
    my ( $self, @devs ) = @_;
    my @pdevs = ();

    foreach my $dev (@devs) {
        if ( exists($self->{'Metastat'}{$dev} ) ) {
            push @pdevs, keys %{ $self->{PhysDevices4Dev}{$dev} };
#                if exists $self->{PhysDevices4Dev}{$dev};
        }
    }
    @pdevs;
}

=head2 C<mponslice>

    @mps = $svm->mponslice( 'c0t0d0s0' );
    @mps = $svm->mponslice( 'c0t0d0s1' );

C<mponslice> returns the list of filesystems present on a physical disk slice.

This information is drawn from two sources: C<Solaris::Disk::Mnttab>, and from the
SVM object hierarchy, so one can ask for mount points on SVM devices.

=cut

sub mponslice($$) {
    my ( $self, $slice ) = @_;
    my @mps;

    if ( defined( $self->{pdev2mp}{$slice} ) ) {
        @mps = keys %{ $self->{pdev2mp}{$slice} };
    }

    @mps;
}

=head2 C<mpondisk>

    @mps = $svm->mpondisk( 'c0t0d0' );
    @mps = $svm->mpondisk( 'c0t0d0s0' ); # idem
    @mps = $svm->mpondisk( 'c0t0d0s1' ); # idem

C<mpondisk> returns the list of filesystems present on a physical disk.

=cut

sub mpondisk($$) {
    my ( $self, $disk ) = @_;
    my %mps;

    $disk = $1 if $disk =~ m/(c\d+t\d+d\d+)/;
    foreach my $i ( 0 .. 7 ) {
        my $slice = "${disk}s$i";
        if ( defined( $self->{pdev2mp}{$slice} ) ) {
            $mps{$_}++ foreach (keys %{ $self->{pdev2mp}{$slice} });
        }
    }

    keys %mps;
}

=head2 C<mpondev>

    @mps = $svm->mpondev( 'd10' );

C<mpondev> returns the list of filesystems present on a SVM device.

=cut

sub mpondev($$) {
    my ( $self, $dev ) = @_;
    my @mps;

    if ( defined( $self->{dev2mp}{$dev} ) ) {
        @mps = keys %{
            $self->{dev2mp}{$dev}
        };
    }
    @mps;
}

=head2 C<devs4mp>

    @devs = $svm->devs4mp( '/export/home' );

C<devs4mp> returns the list of all devices (either the one directly under the
mount point or other devices below) for a given mount point.

=cut

sub devs4mp($$) {
    my ( $self, $mp ) = @_;
    my @devs;

    if ( defined( $self->{mp2dev}{$mp} ) ) {
        @devs =
          ( $self->{mp2dev}{$mp}, $self->getsubdevs( $self->{mp2dev}{$mp} ) );
    }

    @devs;
}

=head2 C<disks4mp>

    @disks = $svm->disks4mp( '/export/home' );

C<disks4mp> returns the list of all physical disks on which is a given mount
point via SVM.

=cut

sub disks4mp($$) {
    my ( $self, $mp ) = @_;
    my @disks;
    if ( defined( $self->{mp2dev}{$mp} ) ) {
        @disks = $self->getphysdevs( $self->{mp2dev}{$mp} );
    }

    return @disks;
}

=head2 C<version>
    
    $version = $svm->version;

C<version> returns the current version of this package.

=cut

sub version { $VERSION }

1;
__END__

=head1 BUGS

Not all methods are implemented (C<dumpconfig>).

Many accessors are missing to the internal data structure, which may lead to
the lost in data structure programer syndrom(tm).

RAID0 device size may not be accurate, particularly when the underlying
devices are of different sizes. Your mileage may vary. This particularity needs
testing and development in regard to the computing model (smallest device size *
number of devices for RAID1).

The test suite has been augmented to cover all possible SVM configuration.
However, these configurations may not be possible with SVM (I do not have access
anymore to a Solaris+SVM machine), thus the module may accept unacceptable
configuration schemes.

I really should take time to create weird configurations, with space loss as in
concat stripes with different size components, and users, such as you, will help
all of us sending me some weird configurations as well. The more data we have to
test against, the more accurate the module will be. If nearly all code pathes
are actually tested, some are better than others. One example is the C<size>
method, which results are B<not> tested against real world figures.

Please report any other bugs or feature requests to
C<bug-solaris-disk-svm@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Solaris-Disk-SVM>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 AUTHOR

Jérôme Fenal <jfenal@free.fr>

You are welcome to send me sample configurations, bug reports or kudos.

=head1 VERSION

This is version 0.02 of the C<Solaris::Disk::SVM> module.

=head1 COPYRIGHT

Copyright (C) 2004, 2005 Jérôme Fenal. All Rights Reserved

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=head1 SEE ALSO

See L<Solaris::Disk::VTOC> to access disk slices information.

See L<Solaris::Disk::Mnttab> to get current mounted devices.

