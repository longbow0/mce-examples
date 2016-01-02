#!/usr/bin/env perl
###############################################################################
## ----------------------------------------------------------------------------
## Barrier synchronization example.
## http://en.wikipedia.org/wiki/Barrier_(computer_science)
##
## MCE::Shared implementation
##    inspired by PDL::Parallel::threads::SIMD
##
###############################################################################

use strict;
use warnings;

use MCE;
use MCE::Shared;
use Time::HiRes qw(time usleep);

my $num_workers = 8;
my $count = MCE::Shared->condvar(0);
my $state = MCE::Shared->scalar('ready');

## Lock is released when calling ->broadcast, ->signal, ->timedwait, or ->wait.
## Thus, re-obtain the lock for synchronization afterwards if desired.

## Sleeping with small values is expensive on Cygwin (imo); 0 to disable.
my $microsecs = ($^O eq 'cygwin') ? 0 : 200;

sub barrier_sync {
    usleep($microsecs) until $state->get eq 'ready' or $state->get eq 'up';

    $count->lock;
    $state->set('up'), $count->incr;

    if ($count->get == $num_workers) {
        $count->decr, $state->set('down');
        $count->broadcast;
    }
    else {
        $count->wait while $state->get eq 'up';
        $count->lock;
        $count->decr;
        $state->set('ready') if $count->get == 0;
        $count->unlock;
    }
}

sub user_func {
   my $id = MCE->wid;
   for (1 .. 400) {
      MCE->print("$_: $id\n");
      barrier_sync();
   }
}

my $start = time();

my $mce = MCE->new(
   max_workers => $num_workers,
   user_func   => \&user_func
)->run;

printf {*STDERR} "\nduration: %0.3f\n\n", time() - $start;

## Time taken from a 2.6 GHz machine running Mac OS X.
##
## threads::shared:   0.238s  threads
##   forks::shared:  36.426s  child processes
##     MCE::Shared:   0.397s  child processes
##        MCE Sync:   0.062s  child processes
##

