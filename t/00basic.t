# in case Test::More ain't there
BEGIN {
    eval { require Test::More; };
    print "1..0\n" and exit if $@;
}

use strict;
use Test::More;
use File::Find;

my @modules;
find( sub {
          return unless /\.pm$/;
          local $_ = $File::Find::name;
          print STDERR "$_\n";
          s!/!::!g;
          s/\.pm$//;
          s/^blib::lib:://;
          push @modules, $_;
      }, 'blib/lib' );


plan tests => scalar @modules;

use_ok($_) for sort @modules;

