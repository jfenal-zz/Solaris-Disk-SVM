package Solaris::Disk::SVM;

use strict;
use warnings;
use Carp;
use Solaris::Disk::VTOC;
use Solaris::Disk::Mnttab;
use Term::ANSIColor;

my $VERSION;
$VERSION = 0.01;

=head1 NAME

Salaris::Disk::SVM

=head1 SYNOPSIS

  my $svm = Solaris::Disk::SVM->new( init => 1 );
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
C<Solaris::Disk::Mnttab> and C<Solaris::Disk::Partitions>.

=cut

sub new {
    my ( $class, @args ) = @_;
    $class = ref($class) || $class;

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
    croak "Unknown parameter(s): @args" if @args;

    # Create the vtoc object, but do initialize it.
    # In case of file based source, it would be initialized explicitely, and
    # further calls to C<readvtoc> by C<readconfig> will shortly return as disk
    # partition already loaded by hand. So init could not be 1 in this case, and
    # readconfig should also be explicitely called.
    $self->{vtoc}   = Solaris::Disk::VTOC->new( init   => 0 );
    $self->{mnttab} = Solaris::Disk::Mnttab->new( init => 0 );
    bless $self, $class;

    if ( defined( $parms{init} ) && $parms{init} == 1 ) {
        $self->readconfig(
            defined( $parms{metastatp} )
            ? ( metastatp => $parms{metastatp} )
            : () );
    }

    return $self;
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
        for ($desc) {

            # A soft partition
            /^\-p.*/ and do {
                @desc = split /\s+/, $desc;
                my %spdesc;
                while ( my $opt = shift @desc ) {
                    if ( $opt eq '-p' ) {
                        $spdesc{slice} = shift @desc;
                    }
                    elsif ( $opt eq '-o' ) {
                        my $offset = shift @desc;
                        push @{ $spdesc{offsets} }, $offset;
                        $opt = shift @desc;
                        if ( $opt eq '-b' ) {
                            push @{ $spdesc{sizes} }, shift @desc;
                        }
                        else {
                            croak
"Soft-partition $dev has no size at offset $offset";
                        }
                    }
                    else {
                        croak "Soft-partition $dev has no offset";
                    }
                }
                $self->{devices}{$dev}{type} = "softpart";

            #            $self->{objtype}{$self->{devices}{$dev}{type}}{$dev}++;
                $self->{objtype}{ $self->{devices}{$dev}{type} }{$dev}{device} =
                  $spdesc{slice};

                push @{ $self->{LeafPhysDevices}{$dev} }, $spdesc{slice};

                #      push @{$SubElements{$dev}}, $spdesc{slice};

                $self->{SPSize}{$dev} = 0;
                foreach my $i ( 0 .. $#{ @{ $spdesc{offsets} } } ) {
                    my $size = @{ $spdesc{sizes} }[$i];
                    push @{ $self->{SPContains}{ $spdesc{slice} } },
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
                  . join( " ", @{ $self->{LeafPhysDevices}{$dev} } )
                  . ", size="
                  . $self->{SPSize}{$dev}
                  . ", offset={"
                  . join( ', ', @{ $self->{SPOffset}{$dev} } ) . "}) ";
                if ( $spdesc{slice} =~ /c\d+t\d+d\d+s\d+/ ) {
                    $self->{Partitions}{ $spdesc{slice} }{use}++;
                }
                last;
            };

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
                            push @{ $self->{LeafPhysDevices}{$dev} }, $el;
                            push @elements, $el;
                            $columns++;
                            last;
                        };
                        /¯-k$/ and do {
                            $self->{devices}{$dev}{kflag}++;
                            last;
                        };
                        /¯-i$/ and do {
                            $self->{devices}{$dev}{iflag} = shift @desc;
                            last;
                        };
                        /¯-o$/ and do {
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
                print STDERR "WARNING : "
                  . $self->{devices}{$dev}{type}
                  . " $dev has only one side\n"
                  if ( @{ $self->{SubElements}{$dev} } == 1 && $self->{debug} );
                last;
            };

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
                        if ( $el eq '-i' ) {
                            shift @desc;
                            $el = shift @desc;
                        }
                        for ($el) {
                            /^d\d+/ and do {
                                push @{ $self->{SubElements}{$dev} }, $el;
                                last;
                            };
                            /^c\d+t\d+d\d+s\d+/ and do {
                                push @{ $self->{LeafPhysDevices}{$dev} }, $el;

                                #   push @{ $self->{SubElements}{$dev} }, $el;
                                $self->{Partitions}{$el}{'use'}++;

                                #              push @{$SubElements{$dev}}, $el;
                                last;
                            };
                        }
                    }
                }

                if ( $nstripe == 1 && $maxconcat == 1 ) {
                    $self->{devices}{$dev}{type} = "device";
                }
                if ( $nstripe > 1 && $maxconcat == 1 ) {
                    $self->{devices}{$dev}{type} = "concat";
                }
                if ( $nstripe == 1 && $maxconcat > 1 ) {
                    $self->{devices}{$dev}{type} = "stripe";
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
    if ( $dev =~ m/^hsp\d+/ ) {

        # FIXME : need to verify the hsp format
        my @desc = split /\s+/, $desc;

        $self->{SubElements}{$dev} = @desc ? @desc : ();
        $self->{devices}{$dev}{type} = 'hotspare';
        if (@desc) {
            $self->{devices}{$dev}{explanation} =
              "$dev is a hotspare ("
              . join( " ", @{ $self->{SubElements}{$dev} } ) . ")";
        }
        else {
            $self->{devices}{$dev}{explanation} =
              "$dev is a hotspare without any disk";

        }
        $self->{objtype}{hotspare}{$dev}{disks} = scalar @desc;
    }
}

=head2 C<readconfig>

  $svm->readconfig( metastatp => 'metastatp.txt' );

C<readconfig> reads a data source in 'metastat -p' format, and creates
configuration from it calling sdscreateobject and propagating device
dependencies.

The C<metastatp> named argument can provide a file source to use instead of
'F<metastat -p |>'.

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
    croak "Unknown parameter(s): @args"
      if @args;

    $self->{metastatSource} = "metastat -p |";  # the default source... maybe
                                                # should we specify full path...

    $self->{metastatSource} = $parms{metastatp} if defined $parms{metastatp};

    open MS, $self->{metastatSource}
      or croak "Cannot open metastat source '$self->{metastatSource}'";
    while (<MS>) {
        next if m/^#/;
        while ( $_ =~ /.*\\\n/ ) {
            chomp;    # chomp terminal \n
            chop;     # chop the terminal \\ for next line
            $_ .= readline(*MS);    # concat next line from MS
        }
        ( $dev, @desc ) = split;
        $self->{Metastat}{$dev} = join " ", @desc;
    }
    close MS;

    # On a maintenant un hash %Metastat qui contient la config brute
    while ( ( $dev, $desc ) = each %{ $self->{Metastat} } ) {
        $self->sdscreateobject( $dev, $desc );
    }

    #
    # Passe pour assigner les physical à tt le monde
    #
    foreach $dev ( keys %{ $self->{Metastat} } ) {
        foreach my $sdev ( $self->getsubdevs($dev) ) {
            if ( defined( @{ $self->{LeafPhysDevices}{$sdev} } ) ) {

#                push @{ $self->{PhysDevices4Dev}{$dev} }, @{ $self->{LeafPhysDevices}{$sdev} };
                foreach my $i ( @{ $self->{LeafPhysDevices}{$sdev} } ) {

                 #                    print STDERR "$sdev is subdev for $dev\n";
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
        if ( $dev =~ m/c\d+t\d+d\d+/ ) {
            $self->{vtoc}->readvtoc( device => $dev );
            $self->{Partitions}{$dev}{size} = $self->{vtoc}->size($dev);
        }
    }
    foreach $dev ( keys %{ $self->{LeafPhysDevices} } ) {
        $self->{vtoc}->readvtoc( device => $dev ) if $dev =~ m/c\d+t\d+d\d+/;
    }

    # A priori, les informations sur les partitions sont maintenant complètes,
    # que ce soit directement par le dernier code, ou par le biais d'une lecture
    # manuelle entre l'init et le readconfig.
    # On peut donc faire les propagations dev2mp, mp2dev, mp2pdev, pdev2mp

    foreach $dev ( keys %{ $self->{mnttab}->{dev2mp} } ) {
        next if $dev !~ m/(?:d\d+|c\d+t\d+d\d+(?:s\d+)*)/;
        my $mnt = $self->{mnttab}->{dev2mp}{$dev};

        #print STDERR "mnt = $mnt\n";
        # Copie dans l'objet svm
        $self->{dev2mp}{$dev} = $mnt;
        $self->{mp2dev}{$mnt} = $dev;
        foreach my $sdev ( $self->getsubdevs($dev) ) {
            $self->{dev2mp}{$sdev}{$mnt}++;
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
        $size = $self->{vtoc}{$disk}{$pn}{'count'};
    }
    elsif ( $dev =~ m/d\d+/ ) {
        if ( defined( $self->{SPSize}{$dev} ) ) {
            $size = $self->{SPSize}{$dev};
        }
        elsif ( scalar @{ $self->{SubElements}{$dev} } ) {
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
            elsif ( $self->{devices}{$dev}{type} eq 'mirror' ) {
                $size = $msize;    # le minima
            }
            elsif ( $self->{devices}{$dev}{type} eq 'raid5' ) {
                $size = $msize * ( scalar(@{ $self->{SubElements}{$dev} }) - 1 );
            }
        }
        elsif ( scalar @{ $self->{LeafPhysDevices}{$dev} } ) {
            my $msize = 1 << 31;    # some maximum value
            foreach my $se ( @{ $self->{LeafPhysDevices}{$dev} } ) {
                my $s = $self->{vtoc}->size($se);
                $size += $s;
                $msize = $s if $s < $msize;
            }
            if ( $self->{devices}{$dev}{type} eq 'mirror' ) {
                $size = $msize;    # le minima
            }
            elsif ( $self->{devices}{$dev}{type} eq 'raid5' ) {
                $size = $msize * ( scalar(@{ $self->{LeafPhysDevices}{$dev} }) - 1 );
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
    print "Apercu de la configuration :\n";
    my @devs = keys %{ $self->{devices} };

    foreach (@devs) {
        s/^d//;
    }

    foreach ( sort { $a <=> $b } @devs ) {
        my $devsize = $self->size( 'd' . $_ ) >> 11;
        print "d$_ ("
          . $self->{devices}{ 'd' . $_ }{type} . ") : "
          . $self->{devices}{ 'd' . $_ }{explanation}
          . "($devsize Mo)\n";
    }
}

=head2 C<dumpconfig>

C<dumpconfig> permettra de sortir la configuration au format metastat -p.

=cut

sub dumpconfig {

    # FIXME
}

=head2 C<showsp>

  $svm->showsp();
  $svm->showsp( "c4t10d0s0" );  # for softparts on disk slice
  $svm->showsp( "d100" );       # for softparts on devices

C<showsp> prints the list of the given soft-partition(s) container.

=cut

sub showsp(@) {
    my ( $self, @devs ) = @_;
    sub _sortbyoffset { $a->[0] <=> $b->[0] }

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
              my $list ( sort _sortbyoffset @{ $self->{SPContains}{$dev} } )
            {
                my $offset   = $list->[0];
                my $size     = $list->[1];
                my $endblock = $offset + $size - 1;

                if ( ( $offset - $precendblock ) > 2 ) {
                    print color('green') if $self->{colour};
                    printf(
                        "%-9s | *FREE* | %10d | %10d | %10d (%5d Mo) | free\n",
                        $dev,
                        $precendblock + 2,
                        $offset - 2,
                        $offset - $precendblock - 3,
                        ( $offset - $precendblock - 3 ) >> 11,
                    );
                    print color('reset') if $self->{colour};
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
                        $self->{vtoc}->{$disk}{$pn}{'count'} -
                        ( $precendblock + 2 )
                    ) > 0
                  )
                {
                    print color('green') if $self->{colour};
                    printf(
                        "%-9s | *FREE* | %10d | %10d | %10d (%5d Mo) | free\n",
                        $dev,
                        $precendblock + 2,
                        $self->{vtoc}->{$disk}{$pn}{'count'},
                        $free, $free >> 11,
                    );
                    print color('reset') if $self->{colour};
                }
                else {
                    print color('red') if $self->{colour};
                    printf( "%-9s | No more free space...\n", $dev );
                    print color('reset') if $self->{colour};
                }
            }
            else {
                my $devsize = $self->size($dev);
                if ( ( my $free = $devsize - $precendblock - 1 ) > 0 ) {
                    print color('green') if $self->{colour};
                    printf(
                        "%-9s | *FREE* | %10d | %10d | %10d (%5d Mo) | free\n",
                        $dev, $precendblock + 2,
                        $devsize, $free, $free >> 11,
                    );
                    print color('reset') if $self->{colour};
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
        my $devsize = getsize($dev) >> 11;
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

    my @devs = keys %{ $self->{devices} };

    foreach (@devs) {
        s/^d//;
    }

    my @sdev = sort { $a <=> $b } @devs;

    $sdev[-1] + 1;
}

=head2 C<isdevfree>

  my $isfree{$dev} = $svm->isdevfree( $dev );

C<isdevfree> take a device name (/d\d/) or a device number in argument
and return 0 if the device is already defined, 1 if the device is not
defined.

=cut

sub isdevfree($$) {
    my ( $self, $dev ) = @_;

    $dev = 'd' . $dev if ( $dev =~ /\d/ );
    if ( exists $self->{Metastat}{$dev} ) {
        explaindev($dev)             if $self->{verbose};
        return 0;
    }
    else {
        return 1;
    }
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
                if ( $cdev =~ /d\d+/ ) {
                    push @subdevs, $self->getsubdevs($cdev);
                }
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
    my @pdevs;
    foreach (@devs) {
        if ( exists( $self->{Metastat}{$_} ) ) {
            push @pdevs, keys %{ $self->{PhysDevices4Dev}{$_} };
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

    $slice = $1 if $slice =~ m/(c\d+t\d+d\d+s\d+)/;
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
    my @mps;

    $disk = $1 if $disk =~ m/(c\d+t\d+d\d+)/;
    foreach my $i ( 0 .. 7 ) {
        my $slice = "${disk}s$i";
        if ( defined( $self->{pdev2mp}{$slice} ) ) {
            push @mps, keys %{ $self->{pdev2mp}{$slice} };
        }
    }

    @mps;
}

=head2 C<mpondev>

    @mps = $svm->mpondev( 'd10' );

C<mpondev> returns the list of filesystems present on a SVM device.

=cut

sub mpondev($$) {
    my ( $self, $dev ) = @_;
    my @mps;

    $dev = $1 if $dev =~ m/(d\d+)/;
    if ( defined( $self->{dev2mp}{$dev} ) ) {
        @mps = keys %{ $self->{dev2mp}{$dev} };
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
        @devs = $self->{mp2dev}{$mp}, $self->getsubdevs( $self->{mp2dev}{$mp} );
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
        @disks = $self->getphysdevs( $self->{mp2pdev}{$mp} );
    }

    @disks;
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
number of devices for RAID1.

The test suite is quite limited as to possible SVM configuration. I really
should take time to create weird configurations, with space loss as in concat
stripes with different size components.

Another good test to implement is a simple C<showconfig>, and see if there are
no 'Use of uninitialized value' warnings. Seems I need to re-read Schwern's
testing tutorial.

=head1 AUTHOR

Jérôme Fenal <jfenal@free.fr>

=head1 VERSION

This is version 0.01 of the C<Solaris::Disk::SVM>.

=head1 COPYRIGHT

Copyright (C) 2004 Jérôme Fenal. All Rights Reserved

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.


=head1 SEE ALSO

See L<Solaris::Disk::Partitions> to access slice information.
See L<Solaris::Disk::Mnttab> to get current mounted devices.

