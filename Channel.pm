package Log::Channel;

=head1 NAME

Log::Channel - yet another logging package

=head1 SYNOPSIS

  use Log::Channel qw(msg);
  my $log = new Log::Channel("topic");
  $log->("this is a log message, by default going to stderr");
  msg "this is the same as the above";
  msg sprintf ("Hello, %s", $user);

  decorate Log::Channel "topic", "timestamp: (topic) ";
  msg "this message will be prefixed with 'timestamp: (topic) '";

  use Log::Dispatch::File;
  Log::Channel::dispatch("topic",
                         new Log::Dispatch::File(name => 'file1',
                                                 min_level => 'info',
                                                 filename  => 'foo.log',
                                                 mode      => 'append'
                                                ));
  msg "now the message, with decorations, will go to the file";

=head1 DESCRIPTION

I<This is alpha software.>

Allows for code to specify channels for delivery of logging messages,
and for users of the code to control the delivery and formatting of
the messages.

=head1 METHODS

=over 4

=cut

use strict;
use Carp;
use Log::Dispatch;
use base qw(Exporter);

use vars qw(@EXPORT_OK $VERSION);
our @EXPORT_OK = qw(msg);
$VERSION = '0.3';

my %AllLogs;
my %Suppressed;

my %Decoration;
my %VALID_DECORATION = (
			"topic" => 1,
			"timestamp" => 1,
			"context" => 1,
		       );

my %Priority;
my %Context;

my $routing;

=item B<new>

  my $log_coderef = new Log::Channel "topic";

Define a new channel for logging messages.  All new logs default to
output to stderr.  Specifying a dispatcher (see dispatch method below)
will override this behavior.  Logs default active, but can be disabled.

Note that the object returned from the constructor is a coderef,
not the usual hashref.
The channel will remember the topic specified when it was
created, prepended by the name of the current package.

Suggested usage is

  sub logme { $log_coderef->(@_) }

So that you can write logging entries like

  logme "This is the message\n";

=cut


sub new {
    my $proto = shift;
    my $class = ref ($proto) || $proto;

    my $topic = (caller)[0];
    $topic = (caller(1))[0] if $topic eq __PACKAGE__; # if called from msg
    if ($_[0]) {
	$topic .= "::" . shift;
    }
    my $config = _config($topic, @_);

    my $self = _makesub($class, $config);
    bless $self, $class;

    $AllLogs{$topic} = $self;

    return $self;
}

sub make {
    my $proto = shift;
    my $class = ref ($proto) || $proto;

    my $topic = shift;
    my $config = _config($topic, @_);

    my $self = _makesub($class, $config);
    bless $self, $class;

    $AllLogs{$topic} = $self;

    return $self;
}

sub _config {
    my ($topic, %config) = @_;

    if (defined $AllLogs{$topic}) {
        carp "There is already an active channel for '$topic'";
    }          

    $config{topic} = $topic;

    return \%config;
}


sub _makesub {
    my ($class, $config) = @_;
    
    *sym = "${class}::_transmit";
    my $transmit = *sym{CODE};
    
    return
      sub {
          return if $Suppressed{$config->{topic}};

	  my $dispatchers = $routing->{$config->{topic}};
	  if ($dispatchers) {
	      foreach my $dispatcher (@$dispatchers) {
		  $dispatcher->log(level => $Priority{$config->{topic}}
				   || "info",
				   message => _construct($config, @_));
	      }
	  } else {
	      $transmit->($config, _construct($config, @_));
	  }
      };

}

=item B<disable>

  disable Log::Channel "topic";

No further log messages will be transmitted on this topic.  Any
dispatchers configured for the channel will not be closed.

A channel can be disabled before it is created.

=cut

sub disable {
    shift if $_[0] eq __PACKAGE__;
    my ($topic) = @_;

#    if ($topic !~ /::/) {
#	$topic = (caller)[0] . "::" . $topic;
#    }

    $Suppressed{$topic}++;
}

=item B<enable>

  enable Log::Channel "topic";

Restore transmission of log messages for this topic.  Any dispatchers
configured for the channel will start receiving the new messages.

=cut

sub enable {
    shift if $_[0] eq __PACKAGE__;
    my ($topic) = @_;

#    if ($topic !~ /::/) {
#	$topic = (caller)[0] . "::" . $topic;
#    }

    delete $Suppressed{$topic};
}

=item B<msg>

  use Log::Channel qw(msg);
  msg "this is my message";

Built-in logging directive.  When exported, this sends the
message to the logging channel that was most recently created in the
current package.  If no channel is explicitly created, msg will deliver
to stderr.

This is not recommended when your package uses more than one channel.

=cut

sub msg {
    my $package = (caller)[0];
    my $channel = $AllLogs{$package} || new Log::Channel;

    $channel->(@_);
}

=item B<decorate>

  decorate Log::Channel "topic", "decoration-string";

Specify the prefix elements that will be included in each message
logged to the channel identified by "topic".  Options include:

  topic - channel topic name, prefixed with package::

  timestamp - current timestamp ('scalar localtime')

The decorator-string can contain these elements with other punctuation,
e.g. "topic: ", "(topic) [timestamp] ", etc.

Comment on performance: It would probably be quicker to parse the
string here and construct a list of items that will be processed
in _construct() rather than doing string replacements. 

=cut

sub decorate {
    shift if $_[0] eq __PACKAGE__;
    my ($topic, $decorator) = @_;

#    if ($topic !~ /::/) {
#	$topic = (caller)[0] . "::" . $topic;
#    }

    $Decoration{$topic} = $decorator;
}


=item B<decorate>

  set_context Log::Channel "topic", $context;

Associated some information (a string) with a log channel, specified
by topic.  This string will be included in log messages if the 'context'
decoration is activated.

This is intended when messages should include reference info that
changes from call to call, such as a current session id, user id,
transaction code, etc.

=cut

sub set_context {
    shift if $_[0] eq __PACKAGE__;
    my ($topic, $context) = @_;

    if ($topic !~ /::/) {
	$topic = (caller)[0] . "::" . $topic;
    }

    $Context{$topic} = $context;
}


sub _construct {
    my ($config) = shift;

    my $prefix = $Decoration{$config->{topic}} or return join("", @_);

    # See performance comment above

    $prefix =~ s/topic/$config->{topic}/;
    $prefix =~ s/timestamp/scalar localtime/e;
    $prefix =~ s/context/$Context{$config->{topic}}/;

    my $text = join("", @_);
#    chomp $text;
    if ($prefix =~ /text/) {
	$prefix =~ s/text/$text/e;
#	return $prefix . "\n";
	return $prefix;
    } else {
#	return $prefix . $text . "\n";
	return $prefix . $text;
    }
    return $prefix . @_;
}


# internal method

sub _transmit {
    my ($config) = shift;

#    print STDERR @_, "\n";
    print STDERR @_;
}


=item B<dispatch>

  dispatch Log::Channel "topic", (new Log::Dispatch::Xyz(...),...);

Map a logging channel to one or more Log::Dispatch dispatchers.

Any existing dispatchers for this channel will be closed.

Dispatch instructions can be specified for a channel that has not
been created.

The only requirement for the dispatcher object is that it supports
a 'log' method.  Every configured dispatcher on a channel will receive
all messages on that channel.

=cut

sub dispatch {
    shift if $_[0] eq __PACKAGE__;
    my ($topic, @dispatchers) = @_;

#    if ($topic !~ /::/) {
#	$topic = (caller)[0] . "::" . $topic;
#    }

    delete $routing->{$topic};

    foreach my $dispatcher (@dispatchers) {
	croak "Expected a Log::Dispatch object"
	  unless UNIVERSAL::can($dispatcher, "log");

	push @{$routing->{$topic}}, $dispatcher;
    }
}

# if we need to be able to associate priority (debug, info, emerg, etc.)
# with each log message, this might be enough.  It's by channel, though,
# not per message.  Since the overhead of creating a channel is minimal,
# I prefer to associate one priority to all messages on the channel.
# This also means that a module developer doesn't have to specify the
# priority of a message - a user of the module can set a particular
# channel to a different priority.
# Valid priority values are not enforced here.  These could potentially
# vary between dispatchers.  UNIX syslog specifies one set of priorities
# (emerg, alert, crit, err, warning, notice, info, debug).
# The log4j project specifies a smaller set (error, warn, info, debug, log).
# Priority ranking is also controlled by the dispatcher, not the channel.

sub set_priority {
    my ($topic, $priority) = @_;

    $Priority{$topic} = $topic;
}


=item B<status>

  status Log::Channel;

Return a blob of information describing the state of all the configured
logging channels, including suppression state, decorations, and dispatchers.

Currently does nothing.

=cut

sub status {
    return;
}


1;

=back

=head1 TEST SUITE

Sorry, don't have one yet.

=head1 AUTHOR

Jason W. May <jmay@pobox.com>

=head1 COPYRIGHT

Copyright (C) 2001,2002 Jason W. May.  All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

  Log::Dispatch and Log::Dispatch::Config
  http://jakarta.apache.org/log4j

And many other logging modules:
  Log::Agent
  CGI::Log
  Log::Common
  Log::ErrLogger
  Log::Info
  Log::LogLite
  Log::Topics
  Log::TraceMessages
  Pat::Logger
  POE::Component::Logger
  Tie::Log
  Tie::Syslog
  Logfile::Rotate
  Net::Peep::Log
  Devel::TraceFuncs
  Devel::TraceMethods

=cut
