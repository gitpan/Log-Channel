#!/usr/bin/perl -w -T
#
# Test for dispatcher behavior
#

use strict;
use Test::Simple tests => 2;

use lib "./blib/lib";
use Log::Channel;
use Log::Dispatch::File;

my $log = new Log::Channel;
sub msg { $log->(@_) }

decorate Log::Channel "main", "topic timestamp: text\n";

my $filename = "/tmp/logchan$$.log";
my $file = Log::Dispatch::File->new( name      => 'file1',
				     min_level => 'info',
				     filename  => $filename,
				     mode      => 'append' );

######################################################################

close STDERR;

my $stderrfile = "/tmp/logchan$$.stderr";
open STDERR, ">$stderrfile" or die;

######################################################################

msg "message 1";

enable Log::Channel "main";

msg "message 2";

dispatch Log::Channel "main", $file;

msg "message 3";

msg "message 4";

close STDERR;
open (LINES, "<$stderrfile") or die $!;
my @lines = <LINES>;
close LINES;
ok (scalar grep { "message 2" } @lines == 1);
ok (scalar grep { "message " } @lines == 2);

unlink $stderrfile;
unlink $filename;
