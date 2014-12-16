use strict;
use vars qw($VERSION %IRSSI);
use Data::Dumper;
use POSIX;
use Time::HiRes qw/sleep/;
use JSON;
use LWP::UserAgent;

use Irssi;
$VERSION = '20111124';
%IRSSI = (
    authors     => 'tuqs',
    contact     => 'tuqs@core.ws',
    name        => 'youtube',
    description => 'shows the title and description from the video',
    license     => 'Public Domain',
   changed     => $VERSION,
);

#
# 20081105 - function rewrite
# 20081226 - fixed regex
# 20090206 - some further fixes
# 20110913 - added support for youtu.be links
# 20111014 - changed regex so that it finds the v parameter even if it's not first
# 20111014 - added &#39; to htmlfix list
# 20111023 - improved regex and now uses youtube api instead
# 20111023 - improved regex some more and added detection of removed videos >:)
# 20111024 - fixed bug that caused certain id's to not work with api, fixed typo
# 20111030 - FIXED.
# 20111101 - added a super regex courtesy of ridgerunner (http://stackoverflow.com/questions/5830387/php-regex-find-all-youtube-video-ids-in-string/5831191#5831191)
# 20111124 - apparently the super regex didn't allow links without http://, so I made that part optional
#
# usage:
# /script load youtube
# enjoy ;o)
#

sub process_message { 
	my ($server, $data, $nick, $address) = @_;
	my ($target, $text) = split(/ :/,$data,2);
	#If we're the target (privmsg), then pivot it back to the sender.
	if (lc($target) eq lc($server->{nick})) {
		$target = $nick;
	} 
	my $url = uri_parse($text);
	if ($url) {
		process_url($server,$target,$url);
	}
	Irssi::signal_continue(@_);
} 
sub event_action {
        my ($server, $text, $nick, $address, $target) = @_;
	#If we're the target (privmsg), then pivot it back to the sender.
	if (lc($target) eq lc($server->{nick})) {
		$target = $nick;
	} 
	my $url = uri_parse($text);
	if ($url) {
		process_url($server,$target,$url);
	}
	Irssi::signal_continue(@_);
}

sub uri_parse { 
    my ($url) = @_; 
    # Super RegEx courtesy of ridgerunner
    # http://stackoverflow.com/questions/5830387/php-regex-find-all-youtube-video-ids-in-string/5831191#5831191
    if ($url =~ /(?:https?:\/\/)?(?:[0-9A-Z-]+\.)?(?:youtu\.be\/|youtube\.com\S*[^\w\-\s])([\w\-]{11})(?=[^\w\-]|$)(?![?=&+%\w]*(?:['"][^<>]*>|<\/a>))[?=&+%\w]*/ig) { 
        return "http://gdata.youtube.com/feeds/api/videos/$1?v=2&alt=jsonc";
    } 
    return 0; 
} 

sub uri_get { 
	my ($url) = @_; 

	if ($url) {
		my $ua = LWP::UserAgent->new(env_proxy=>1, keep_alive=>1, timeout=>5); 
		$ua->agent("irssi/$VERSION " . $ua->agent()); 

		my $req = HTTP::Request->new('GET', $url); 
		my $res = $ua->request($req);

		my $result_string = '';
		my $json = JSON->new->utf8;

		eval {
			my $json_data = $json->decode($res->content());

			if ($res->is_success()) { 
				eval {
				$result_string = $json_data->{data}->{title};
			} or do {
					$result_string = "Request successful, parsing error";
				};
			} 
			else {
				eval {
					$result_string = "Error $json_data->{error}->{code} $json_data->{error}->{message}";
				} or do {
					$result_string = "Parsing error";
				};
			}
		}
		or do {
			$result_string = "Error " . $res->status_line;
		};

		chomp $result_string;
		return $result_string; 
	}
} 

# When we get data back from the pipe
sub show_result {
	my $args = shift;
	my ($read_handle, $input_tag_ref, $job) = @$args;

	# Read the result
	my $line=<$read_handle>;
	close($read_handle);
	Irssi::input_remove($$input_tag_ref);
	my ($server_tag,$target,$retval) = split("~~~SEP~~~",$line,3);
	if (!$server_tag || !$target || !$retval) {
		Irssi::print("Didn't receive usable data from child.");
		return;
	}

	chomp $retval;	

	my $server = Irssi::server_find_tag($server_tag);
	if (!$server) {
		Irssi::print("Failed to find $server_tag in server tag list.");
		return;
	}
	$server->command("msg $target YouTube: $retval") if $retval;
}


sub process_url {
	my ($server, $target, $url) = @_;
	my ($parent_read_handle, $child_write_handle);


	# Setup the interprocess communication pipe
	pipe($parent_read_handle, $child_write_handle);

	my $oldfh = select($child_write_handle);
	$| = 1;
	select $oldfh;

	# Split off a child process.
	my $pid = fork();
	if (not defined $pid) {
        	print("Can't fork: Aborting");
	        close($child_write_handle);
        	close($parent_read_handle);
	        return;
	}

	if ($pid > 0) { # this is the parent (Irssi)
		close ($child_write_handle);
		Irssi::pidwait_add($pid);
		my $job = $pid;
		my $tag;
		my @args = ($parent_read_handle, \$tag, $job);
		#Spin up the output listener.
	        $tag = Irssi::input_add(fileno($parent_read_handle),
			Irssi::INPUT_READ,
			\&show_result,
			\@args);

	} else { # child
		my $description = uri_get($url);
		my $server_tag = $server->{tag};

		print $child_write_handle "$server_tag~~~SEP~~~$target~~~SEP~~~" . $description . "\n";
		close($child_write_handle);
		POSIX::_exit(1);
	}
}


Irssi::signal_add_last('message irc action', 'event_action');
Irssi::signal_add_last('event privmsg', 'process_message'); 
