package Plugins::SqueezeCloud::Settings;

# Plugin to stream audio from SoundCloud streams
#
# Released under GNU General Public License version 2 (GPLv2)
# Written by David Blackman (first release), Robert Gibbon (improvements),
#   Daniel Vijge (improvements)
# See file LICENSE for full license details

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $log   = logger('plugin.squeezecloud');
my $prefs = preferences('plugin.squeezecloud');

sub name {
	return 'PLUGIN_SQUEEZECLOUD';
}

sub page {
	return 'plugins/SqueezeCloud/settings/basic.html';
}

sub prefs {
	return (preferences('plugin.squeezecloud'), qw(apiKey playmethod disablePeerVerification));
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;
	
	# Fix for Sonology devices where SSL is not working properly
	# Suggested by erland: http://forums.slimdevices.com/showthread.php?92723-Soundcloud-plugin-for-squeezeserver&p=785794&viewfull=1#post785794
	eval "use IO::Socket::SSL";
	if(!$@ && IO::Socket::SSL->can("set_client_defaults")) {
		if($params->{'pref_disablePeerVerification'} eq "disable") {
			$log->info('Disabling SSL peer verification');
			IO::Socket::SSL::set_client_defaults('SSL_verify_mode' => 0x0);
		}
		else {
			$log->info('Enabling SSL peer verification');
			IO::Socket::SSL::set_client_defaults('SSL_verify_mode' => 0x1);
		}
	}

	return $class->SUPER::handler($client, $params)
}

1;
