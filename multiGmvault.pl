#!/usr/bin/perl -w

=head1 NAME

multiGmvault.pl - Backup multiple google mail accounts with gmvault

=head1 SYNOPSIS

multiGmvault.pl [options] file

options: 
[--help] [--man] [--temppath]
[--dbpath] --key --secret

=head1 OPTIONS

=over 4

=item B<-h,-?,--help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<This program> will read the given input file(s) and do something
useful with the contents thereof.

=cut

use strict;
use warnings;
use threads;
use POSIX;
use Benchmark;
use File::Path qw(make_path remove_tree);
use IPC::System::Simple qw(system systemx capture capturex);
use IPC::Cmd qw(can_run run);
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;

my $start_time = new Benchmark;

my $threadcount = 4;
my $gmv_conf_path= $ENV{"HOME"}."/.gmvault";


our $db_path='mutligmvault_db';
our $gmv_path = can_run('gmvault') or die("ERROR: gmvault is not installed or not in the path!");
our $temp_path = 'multigmvault-temp';
our $log_path = 'multigmvault-logs';



our($oauth_ck, $oauth_cs, $help, $man);

GetOptions(	"key=s" => \$oauth_ck,
		"secret=s" => \$oauth_cs,
		"help|?" => \$help,
		"db-path=s" => \$db_path,
		"temp-path|t=s" => \$temp_path,
		"threads|T=i" => \$threadcount,
		"logpath=s" => \$log_path,
		"man" => \$man) or pod2usage(-verbose => 1) && exit;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

unless (defined($oauth_ck) && defined($oauth_cs)) {
	pod2usage(-exitstatus => 2);
}
pod2usage("$0: No file given.") if ((@ARGV == 0) && (-t STDIN));
our $datafile = $ARGV[0];

# Create directories if needed
if (!-d $temp_path){
	make_path($temp_path) or die("Failed to create Temp Path: [$temp_path] ($!)");
}
if (!-d $gmv_conf_path){
	make_path($gmv_conf_path) or die("Failed to create gmvault config path: [$gmv_conf_path] ($!)");
}
if (!-d $log_path){
	make_path($log_path) or die("Failed to create log path: [$log_path] ($!)");
}


print "Using Account data from: $datafile\n";
my @data_num_lines = split(' ', `wc -l $datafile`);
print "Number of accounts to process: $data_num_lines[0]\n";

# Split datafile into parts for threads to work on
my $linecnt = ceil($data_num_lines[0] / $threadcount);
my $splitcmd = "split -d -l $linecnt $datafile $temp_path/thread-split.";
system("rm -f $temp_path/thread-split.*");
if($? != 0) {
	print "ERROR: Deleting temp data in $temp_path\n";
	exit(0);
}
system($splitcmd);
if($? != 0) {
	print "ERROR: Spliting $datafile into thread working parts\n";
	exit(0);
}

my @files = <$temp_path/*>;
my $threads = @files;
print "Number of threads to run: $threads\n";

# Get OAuth files created for all accounts in datafile
print "Storing OAuth credentials for accounts in: $gmv_conf_path\n";
open(F,$datafile) or die("Could not open $datafile: ($!)");
foreach my $line (<F>){
	chomp($line);
#	print "$line\n";
	open(OAUTH,">$gmv_conf_path/$line.oauth") or die("Failed open oauth file: ($!)");
	print OAUTH $oauth_ck."::".$oauth_cs."::two_legged";
	close(OAUTH);
	
}
close(F);

print "Processing accounts:\n";

foreach my $split_file (@files){
 	my $thr = threads->new(\&thread_proccessAccounts, $split_file);
    	#$thr->detach;
}

foreach my $thrList (threads->list) { 
        # Don't join the main thread or ourselves 
        if ($thrList->tid && !threads::equal($thrList, threads->self)) { 
            $thrList->join; 
        } 
}

print "Complete\n";
my $end_time = new Benchmark;
my $diff = timediff($end_time, $start_time);
print "Time taken was ", timestr($diff, 'all'), "\n"; 

sub thread_proccessAccounts {
	my $accounts = shift;
	open(FH, $accounts) or die("Failed to open thread file: ($!)");
	foreach my $account (<FH>){
		my $timestamp = localtime;
		my $tid = threads->tid();
		print "[$timestamp]: Thread: $tid ..... $account";
		my $gmvcmd = $gmv_path . " sync -2 --emails-only --no-compression -d " . $db_path ."/".$account." ".$account." > ".$log_path."/".$account.".xfer.log 2>&1";
		$gmvcmd =~ s/\r|\n//g;
		#print "[$gmvcmd]\n";
		system("$gmvcmd");
		
	}
	close(FH);
}


#sleep 5;



