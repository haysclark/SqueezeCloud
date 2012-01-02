package Plugins::SoundCloud::Plugin;

# Plugin to stream audio from SoundCloud streams
#
# Released under GPLv2

# TODO
# figure out why spaces are getting translated to periods
# uri escape things
# add optional user to title
# can we show description?
# is there pagination for /tracks
# get search working -- tags, query
# get accounts working <-- long way off

use strict;

use vars qw(@ISA);

use URI::Escape;
use JSON::XS::VersionOneAndTwo;
use File::Spec::Functions qw(:ALL);
use List::Util qw(min max);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;

use Data::Dumper;

use Plugins::SoundCloud::ProtocolHandler;

my $log;
my $compat;
my $CLIENT_ID = "ff21e0d51f1ea3baf9607a1d072c564f";

BEGIN {
	$log = Slim::Utils::Log->addLogCategory({
		'category'     => 'plugin.youtube',
		'defaultLevel' => 'INFO',
		'description'  => string('PLUGIN_SOUNDCLOUD'),
	}); 

	# Always use OneBrowser version of XMLBrowser by using server or packaged version included with plugin
	if (exists &Slim::Control::XMLBrowser::findAction) {
		$log->info("using server XMLBrowser");
		require Slim::Plugin::OPMLBased;
		push @ISA, 'Slim::Plugin::OPMLBased';
	} else {
		$log->info("using packaged XMLBrowser: Slim76Compat");
		require Slim76Compat::Plugin::OPMLBased;
		push @ISA, 'Slim76Compat::Plugin::OPMLBased';
		$compat = 1;
	}
}

my $prefs = preferences('plugin.youtube');

$prefs->init({ prefer_lowbitrate => 0, recent => [] });

tie my %recentlyPlayed, 'Tie::Cache::LRU', 20;

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed   => \&toplevel,
		tag    => 'youtube',
		menu   => 'radios',
		is_app => $class->can('nonSNApps') ? 1 : undef,
		weight => 10,
	);

	Slim::Menu::TrackInfo->registerInfoProvider( youtube => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );

	Slim::Menu::TrackInfo->registerInfoProvider( youtubevideo => (
		after => 'bottom',
		func  => \&webVideoLink,
	) );

	Slim::Menu::ArtistInfo->registerInfoProvider( youtube => (
		after => 'middle',
		func  => \&artistInfoMenu,
	) );

	Slim::Menu::GlobalSearch->registerInfoProvider( youtube => (
		after => 'middle',
		name  => 'PLUGIN_SOUNDCLOUD',
		func  => \&searchInfoMenu,
	) );

	if (!$::noweb) {
		require Plugins::SoundCloud::Settings;
		Plugins::SoundCloud::Settings->new;
	}

	for my $recent (reverse @{$prefs->get('recent')}) {
		$recentlyPlayed{ $recent->{'url'} } = $recent;
	}

	Slim::Control::Request::addDispatch(['youtube', 'info'], [1, 1, 1, \&cliInfoQuery]);
}

sub shutdownPlugin {
	my $class = shift;

	$class->saveRecentlyPlayed('now');
}

sub getDisplayName { 'PLUGIN_SOUNDCLOUD' }

sub playerMenu { shift->can('nonSNApps') ? undef : 'RADIO' }

sub updateRecentlyPlayed {
	my ($class, $info) = @_;

	$recentlyPlayed{ $info->{'url'} } = $info;

	$class->saveRecentlyPlayed;
}

sub saveRecentlyPlayed {
	my $class = shift;
	my $now   = shift;

	unless ($now) {
		Slim::Utils::Timers::killTimers($class, \&saveRecentlyPlayed);
		Slim::Utils::Timers::setTimer($class, time() + 10, \&saveRecentlyPlayed, 'now');
		return;
	}

	my @played;

	for my $key (reverse keys %recentlyPlayed) {
		unshift @played, $recentlyPlayed{ $key };
	}

	$prefs->set('recent', \@played);
}

sub toplevel {
	my ($client, $callback, $args) = @_;

	$callback->([
		{ name => string('PLUGIN_SOUNDCLOUD_HOT'), type => 'link',   
		  url  => \&tracksHandler, passthrough => [ { params => 'order=hotness' } ], },

    { name => string('PLUGIN_SOUNDCLOUD_NEW'), type => 'link',   
		  url  => \&tracksHandler, passthrough => [ { params => 'order=created_at' } ], },

    { name => string('PLUGIN_SOUNDCLOUD_SEARCH'), type => 'search',   
		  url  => \&tracksHandler, passthrough => [ { params => 'order=hotness' } ], },

    { name => string('PLUGIN_SOUNDCLOUD_TAGS'), type => 'search',   
		  url  => \&tracksHandler, passthrough => [ { type => 'tags', params => 'order=hotness' } ], },


#		{ name => string('PLUGIN_YOUTUBE_PLAYLISTSEARCH'), type => 'search',
#		  url  => \&searchHandler, passthrough => [ 'playlists/snippets', \&_parsePlaylists ] },

#		{ name => string('PLUGIN_YOUTUBE_RECENTLYPLAYED'), url  => \&recentHandler, },

		{ name => string('PLUGIN_SOUNDCLOUD_URL'), type => 'search', url  => \&urlHandler, },
	]);
}

sub urlHandler {
	my ($client, $callback, $args) = @_;

	my $url = $args->{'search'};
# awful hacks, why are periods being replaced?
  $url =~ s/ com/.com/;
  $url =~ s/www /www./;

  $log->warn($args->{'search'});
  # TODO: url escape this
  my $queryUrl = "http://api.soundcloud.com/resolve.json?url=$url&client_id=$CLIENT_ID";
  $log->warn($queryUrl);

  my $fetch = sub {
		Slim::Networking::SimpleAsyncHTTP->new(
			sub {
				my $http = shift;
				my $json = eval { from_json($http->content) };
				
				if ($@) {
					$log->warn($@);
				}
				
        use Data::Dumper;
        $log->warn(Dumper($json));
        $log->warn($json->{'streamable'});
        $callback->({
          items => [ {
            name => $json->{'title'},
            type => 'audio',
            url  => $json->{'permalink_url'},
            play => $json->{'stream_url'} . "?client_id=$CLIENT_ID",
            icon => $json->{'artwork_url'} || "",
            cover => $json->{'artwork_url'} || "",
          } ]
        })
			},
			sub {
				$log->warn("error: $_[1]");
				$callback->([ { name => $_[1], type => 'text' } ]);
			},
		)->get($queryUrl);
	};
		
	$fetch->();


#				$callback->({
#					items => [ {
#						name => $meta->{'title'},
#						url  => $url,
#						type => 'audio',
#						icon => $meta->{'icon'},
#						cover=> $meta->{'cover'},
#					} ]
#				});
#			} else {
#				$callback->([ { name => string('PLUGIN_YOUTUBE_BADURL'), type => 'text' } ]);
#			}
#		}
}

sub recentHandler {
	my ($client, $callback, $args) = @_;

	my @menu;

	for my $item(reverse values %recentlyPlayed) {
		unshift  @menu, {
			name => $item->{'name'},
			url  => $item->{'url'},
			icon => $item->{'icon'},
			type => 'audio',
		};
	}

	$callback->({ items => \@menu });
}

sub tracksHandler {
	my ($client, $callback, $args, $passDict) = @_;

	# use paging on interfaces which allow otherwise fetch 200 entries for button mode
	my $index    = ($args->{'index'} || 0); # ie, offset
	my $quantity = $args->{'quantity'} || 200;
  my $searchStr = ($passDict->{'type'} eq 'tags') ? "tags=$args->{search}" : "q=$args->{search}";
	my $search   = $args->{'search'} ? $searchStr : '';

  $log->warn(Dumper($passDict));

  my $params = $passDict->{'params'} || '';
  $log->warn($params);

  $log->warn("index: " . $index);
  $log->warn("quantity: " . $quantity);
	
	my $menu = [];
	
	# fetch in stages as api only allows 50 items per response, cli clients require $quantity responses which can be more than 50
	my $fetch;
	
	# FIXME: this could be sped up by performing parallel requests once the number of responses is known??

	$fetch = sub {
    # in case we've already fetched some of this page, keep going
		my $i = $index + scalar @$menu;
    $log->warn("i: " + $i);
		my $max = min($quantity - scalar @$menu, 200); # api allows max of 200 items per response
    $log->warn("max: " + $max);
		
    # todo, formatting
    # todo, offset/limit/etc
    # TODO: make these params work
		my $queryUrl = "http://api.soundcloud.com/tracks.json?client_id=$CLIENT_ID&offset=$i&limit=$quantity&filter=streamable&" . $params . "&" . $search;

		$log->warn("fetching: $queryUrl");
		
		Slim::Networking::SimpleAsyncHTTP->new(
			
			sub {
				my $http = shift;
				my $json = eval { from_json($http->content) };
				
				if ($@) {
					$log->warn($@);
				}
				
      for my $entry (@$json) {
          if ($entry->{'streamable'}) {
            push @$menu, {
              name => $entry->{'title'},
              type => 'audio',
              on_select => 'play',
              playall => 0,
              url  => $entry->{'permalink_url'},
              play => $entry->{'stream_url'} . "?client_id=$CLIENT_ID",
              icon => $entry->{'artwork_url'} || "",
            };
          }
        }
  
        # max offset = 8000, max index = 200 sez soundcloud http://developers.soundcloud.com/docs#pagination
        my $total = 8000 + $quantity;
				
				$log->info("this page: " . scalar @$menu . " total: $total");

        # TODO: check this logic makes sense
				if (scalar @$menu < $quantity) {
          $total = $index + @$menu;
          $log->debug("short page, truncate total to $total");
        }
					
					$callback->({
						items  => $menu,
						offset => $index - 1,
						total  => $total,
					});
			},
			
			sub {
				$log->warn("error: $_[1]");
				$callback->([ { name => $_[1], type => 'text' } ]);
			},
			
		)->get($queryUrl);
	};
		
	$fetch->();
}

sub _parseVideos {
	my ($json, $menu) = @_;
	for my $entry (@{$json->{'entry'} || []}) {
		my $mg = $entry->{'media$group'};
		push @$menu, {
			name => $mg->{'media$title'}->{'$t'},
			type => 'audio',
			on_select => 'play',
			playall => 0,
			url  => 'youtube://' . $mg->{'yt$videoid'}->{'$t'},
			play => 'youtube://' . $mg->{'yt$videoid'}->{'$t'},
			icon => $mg->{'media$thumbnail'}->[0]->{'url'},
		};
	}
}

sub _parseChannels {
	my ($json, $menu) = @_;
	for my $entry (@{$json->{'entry'} || []}) {
		my $title = $entry->{'title'}->{'$t'} || $entry->{'summary'}->{'$t'} || 'No Title';
		$title = Slim::Formats::XML::unescapeAndTrim($title);
		push @$menu, {
			name => $title,
			type => 'link',
			url  => \&searchHandler,
			passthrough => [ $entry->{'gd$feedLink'}->[0]->{'href'}, \&_parseVideos ],
		};
	}
}

sub _parsePlaylists {
	my ($json, $menu) = @_;
	for my $entry (@{$json->{'entry'} || []}) {
		my $title = $entry->{'title'}->{'$t'} || $entry->{'summary'}->{'$t'} || 'No Title';
		$title = Slim::Formats::XML::unescapeAndTrim($title);
		push @$menu, {
			name => $title,
			type => 'link',
			url  => \&searchHandler,
			passthrough => [ $entry->{'content'}->{'src'}, \&_parseVideos ],
		};
	}
}

sub trackInfoMenu {
	my ($client, $url, $track, $remoteMeta) = @_;
	
	my $artist = ($remoteMeta && $remoteMeta->{artist}) || ($track && $track->artistName);

	$artist = URI::Escape::uri_escape_utf8($artist);

	if ($artist) {
		return {
			type      => 'opml',
			name      => string('PLUGIN_YOUTUBE_ON_YOUTUBE'),
			url       => sub {
				my ($client, $callback, $args) = @_;
				$args->{'search'} = $artist;
				$args->{'searchmax'} = 200; # only get 200 entries within context menu
				my $cb = !$compat ? $callback : sub { $callback->(shift->{'items'}) };
				searchHandler($client, $cb, $args, 'videos', \&_parseVideos);
			},
			favorites => 0,
		};
	} else {
		return {};
	}
}

sub artistInfoMenu {
	my ($client, $url, $obj, $remoteMeta) = @_;
	
	my $artist = ($remoteMeta && $remoteMeta->{artist}) || ($obj && $obj->name);

	$artist = URI::Escape::uri_escape_utf8($artist);

	if ($artist) {
		return {
			type      => 'opml',
			name      => string('PLUGIN_YOUTUBE_ON_YOUTUBE'),
			url       => sub {
				my ($client, $callback, $args) = @_;
				$args->{'search'} = $artist;
				$args->{'searchmax'} = 200; # only get 200 entries within context menu
				my $cb = !$compat ? $callback : sub { $callback->(shift->{'items'}) };
				searchHandler($client, $cb, $args, 'videos', \&_parseVideos);
			},
			favorites => 0,
		};
	} else {
		return {};
	}
}

sub webVideoLink {
	my ($client, $url) = @_;

	if (my $id = Plugins::SoundCloud::ProtocolHandler->_id($url)) {

		my $show;
		my $i = 0;
		while (my $caller = (caller($i++))[3]) {
			if ($caller =~ /Slim::Web::Pages/) {
				$show = 1;
				last;
			}
			if ($caller =~ /cliQuery/) {
				if ($client->can('controllerUA') && $client->controllerUA =~ /iPeng/) {
					$show = 1;
				}
				last;
			}
		}

		if ($show) {
			return {
				type    => 'text',
				name    => string('PLUGIN_YOUTUBE_WEBLINK'),
				weblink => "http://www.youtube.com/watch?v=$id",
				jive => {
					actions => {
						go => {
							cmd => [ 'youtube', 'info' ],
							params => {
								id => $id,
							},
						},
					},
				},
			};
		}
	}

	return undef;
}

sub searchInfoMenu {
	my ($client, $tags) = @_;

	my $query = $tags->{'search'};

	$query = URI::Escape::uri_escape_utf8($query);

	return {
		name => string('PLUGIN_SOUNDCLOUD'),
		items => [
			{
				name => string('PLUGIN_YOUTUBE_SEARCH'),
				type => 'link',
				url  => sub {
					my ($client, $callback, $args) = @_;
					$args->{'search'} = $query; 
					my $cb = !$compat ? $callback : sub { $callback->(shift->{'items'}) };
					searchHandler($client, $cb, $args, 'videos', \&_parseVideos);
				},
				favorites => 0,
			},
			{
				name => string('PLUGIN_YOUTUBE_MUSICSEARCH'),
				type => 'link',
				url  => sub {
					my ($client, $callback, $args) = @_;
					$args->{'search'} = $query; 
					my $cb = !$compat ? $callback : sub { $callback->(shift->{'items'}) };
					searchHandler($client, $cb, $args, 'videos', \&_parseVideos, 'category=music');
				},
				favorites => 0,
			},
		   ],
	};
}

# special query to allow weblink to be sent to iPeng
sub cliInfoQuery {
	my $request = shift;
	
	if ($request->isNotQuery([['youtube'], ['info']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $id = $request->getParam('id');

	$request->addResultLoop('item_loop', 0, 'text', string('PLUGIN_YOUTUBE_PLAYLINK'));
	$request->addResultLoop('item_loop', 0, 'weblink', "http://www.youtube.com/v/$id");
	$request->addResult('count', 1);
	$request->addResult('offset', 0);
	
	$request->setStatusDone();
}

1;