#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper qw ( Dumper );
use LWP::UserAgent ();
use POSIX qw( strftime );
use Time::HiRes qw( gettimeofday );

# ======================================================================

my $API_KEY = 'XMu6upOoauZr5EgcETNpDL3f8Kwj9XDXdBUKoRFGNS9WzqfuBd';
my $API_HOST = 'http://api.tumblr.com/v2';

my $ua = LWP::UserAgent->new();
$ua->agent( "tumblr-backup" );

# ======================================================================
# utility

sub xlog
{
    my ( $sec, $usec ) = gettimeofday;
    my $ts = ( strftime( '%Y-%m-%dT%H:%M:%S', gmtime $sec ) .
               sprintf( '.%06dZ', $usec ) );
    print STDERR "$0: $ts: ", @_, "\n";
}

sub check_args
{
    my ( $api, $args_href, $req_args_aref, $opt_args_aref ) = @_;

    if ( my @missing = sort grep { ! exists $args_href->{$_} } @$req_args_aref )
    {
        warn "$api: missing args: @missing\n";
    }

    my %copy = %$args_href;
    foreach my $known_arg ( @$req_args_aref, @$opt_args_aref )
    {
        delete $copy{$known_arg};
    }
    if ( my @unknown = sort keys %copy )
    {
        warn "$api: unknown args: @unknown\n";
    }
}

sub url_encode
{
    my ( $in ) = @_;
    my $out = $in;
    $out =~ s!([^A-Za-z0-9])!sprintf '%%%02x', $1!ge;
    return $out;
}

sub create_api_url
{
    my ( $api, $args_href ) = @_;

    my ( $type, $call ) = split '/', $api;

    my $thing = delete $args_href->{_thing};

    my $url = "$API_HOST/$type/$thing/$call";

    my $sep = '?';
    for my $param ( sort keys %$args_href )
    {
        my $val = url_encode $args_href->{$param};
        $url .= $sep . $param . "=" . $val;
        $sep = '&';
    }

    return $url;
}

sub parse_json
{
    my ( $json ) = @_;

    my $rv = {};
    my $cur = $rv;
    my $last = '_root';
    my @dicts;
    while ( $json =~ m! ( \{ )                     | # $1 - open dict
                        ( \} )                     | # $2 - close dict
                        \s* ( : ) \s*              | # $3 - colon
                        ( , ) \s*                  | # $4 - comma
                        " ( (?: \\" | [^"]+ )* ) " | # $5 - double-quoted string
                        ' ( (?: \\' | [^']+ )* ) ' | # $6 - single-quoted string
                        ( true | false )           | # $7 - boolean literal
                        ( [+-]? (?: \d+\.? | \d*\.\d+ )(?:[eE][+-]?\d+)? )
                                                     # $8 - numeric literal
                      !xg )
    {
        if ( defined $1 )
        {
            die "unable to assign dict without name\n"
              unless defined $last;
            # xlog "json: pushing dict for '$last'";
            push @dicts, $cur;
            $cur->{$last} = {};
            $cur = $cur->{$last};
            undef $last;
            next;
        }
        elsif ( defined $2 )
        {
            warn "pending assign at end of dict\n"
              if defined $last;
            # xlog "json: popping dict";
            $cur = pop @dicts;
            next;
        }
        elsif ( defined $3 )
        {
            warn "colon without name\n"
              unless defined $last;
            next;
        }
        elsif ( defined $4 )
        {
            warn "comma with pending name\n"
              if defined $last;
            next;
        }

        my $val;

        if ( defined $5 )
        {
            $val = $5;
            $val =~ s!(\\.)!"$1"!ge;
            $val =~ s!\\/!/!g;
        }
        elsif ( defined $6 )
        {
            $val = $6;
        }
        elsif ( defined $7 )
        {
            $val = ( $7 eq 'true' );
        }
        elsif ( defined $8 )
        {
            $val = $8 + 0;
        }
        else
        {
            warn "no idea what's going on\n";
        }

        if ( defined $last )
        {
            $cur->{$last} = $val;
            # xlog "json: '$last' = '$val'";
            undef $last;
        }
        else
        {
            $last = $val;
            # xlog "json: last = '$last'";
        }
    }

    return $rv->{_root};
}

sub check_api_result
{
    my ( $api, $dict ) = @_;

    unless ( $dict->{meta}->{status} == 200 )
    {
        die "error calling $api: $dict->{meta}->{msg}\n";
    }
}

# ======================================================================
# API calls

sub api_blog_info
{
    my %args = @_;

    my $api = 'blog/info';
    my @required_args = qw( base-hostname api_key );
    my @optional_args = qw();
    check_args $api, \%args, \@required_args, \@optional_args;

    $args{_thing} = delete $args{'base-hostname'};

    my $url = create_api_url $api, \%args;
    # xlog "url: '$url'";

    my $resp = $ua->get( $url );
    my $dict = parse_json $resp->content();
    check_api_result $api, $dict );
}

# ======================================================================
# main

for my $feed ( @ARGV )
{
    $feed =~ s!^https?://!!;
    $feed =~ s!/+$!!;
    unless ( $feed =~ m!\.tumblr\.com$! )
    {
        $feed .= '.tumblr.com';
    }

    api_blog_info 'base-hostname' => $feed, api_key => $API_KEY;
}
