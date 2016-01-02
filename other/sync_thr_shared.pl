#!/usr/bin/env perl
###############################################################################
## ----------------------------------------------------------------------------
## Barrier synchronization example.
## http://en.wikipedia.org/wiki/Barrier_(computer_science)
##
## threads::shared / forks::shared implementation
##    inspired by PDL::Parallel::threads::SIMD
##
###############################################################################

use strict;
use warnings;

use threads;           # (also try) use forks; use forks::shared;
use threads::shared;

use MCE;
use Time::HiRes qw(time usleep);

my $num_workers   = 8;
my $count :shared = 0;
my $state :shared = 'ready';

## Sleeping with small values is expensive on Cygwin (imo); 0 to disable.
my $microsecs = ($^O eq 'cygwin') ? 0 : 200;

sub barrier_sync {
   usleep($microsecs) until $state eq 'ready' or $state eq 'up';

   lock $count;
   $state = 'up', $count++;

   if ($count == $num_workers) {
      $count--, $state = 'down';
      cond_broadcast($count);
   }
   else {
      cond_wait($count) while $state eq 'up';
      $count--;
      $state = 'ready' if $count == 0;
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

