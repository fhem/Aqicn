###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################
##
##
## Das JSON Modul immer in einem eval aufrufen
# $data = eval{decode_json($data)};
#
# if($@){
#   Log3($SELF, 2, "$TYPE ($SELF) - error while request: $@");
#  
#   readingsSingleUpdate($hash, "state", "error", 1);
#
#   return;
# }
#
#######
#######
#  URLs zum Abrufen diverser Daten
# http://<ip-Powerwall>/api/system_status/soe 
# http://<ip-Powerwall>/api/meters/aggregates
# http://<ip-Powerwall>/api/site_info
# http://<ip-Powerwall>/api/sitemaster
# http://<ip-Powerwall>/api/powerwalls
# http://<ip-Powerwall>/api/networks
# http://<ip-Powerwall>/api/system/networks
# http://<ip-Powerwall>/api/operation
#
##
##



package main;


my $missingModul = "";

use strict;
use warnings;

use HttpUtils;
eval "use Encode qw(encode encode_utf8 decode_utf8);1" or $missingModul .= "Encode ";
eval "use JSON;1" or $missingModul .= "JSON ";


my $version = "0.0.44";




# Declare functions
sub Aqicn_Attr(@);
sub Aqicn_Define($$);
sub Aqicn_Initialize($);
sub Aqicn_Get($$@);
sub Aqicn_Notify($$);
sub Aqicn_GetData($;$);
sub Aqicn_Undef($$);
sub Aqicn_ResponseProcessing($$$);
sub Aqicn_ReadingsProcessing_SearchStationResponse($$);
sub Aqicn_ReadingsProcessing_AqiResponse($);
sub Aqicn_ErrorHandling($$$);
sub Aqicn_WriteReadings($$);
sub Aqicn_Timer_GetData($);
sub Aqicn_AirPollutionLevel($$);




my %paths = (   'statussoe'         => 'system_status/soe',
                'aggregates'        => 'meters/aggregates',
                'siteinfo'          => 'site_info',
                'sitemaster'        => 'sitemaster',
                'powerwalls'        => 'powerwalls',
                'registration'      => 'customer/registration',
                'status'            => 'status'
);


sub Aqicn_Initialize($) {

    my ($hash) = @_;
    
    # Consumer
    $hash->{GetFn}      = "Aqicn_Get";
    $hash->{DefFn}      = "Aqicn_Define";
    $hash->{UndefFn}    = "Aqicn_Undef";
    $hash->{NotifyFn}   = "Aqicn_Notify";
    
    $hash->{AttrFn}     = "Aqicn_Attr";
    $hash->{AttrList}   = "interval ".
                          "disable:1 ".
                          "language:de,en".
                          $readingFnAttributes;
    
    foreach my $d(sort keys %{$modules{Aqicn}{defptr}}) {
    
        my $hash = $modules{Aqicn}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

sub Aqicn_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );
    
    
    if( $a[2] =~ /^token=/ ) {
        $a[2] =~ m/token=([^\s]*)/;
        $hash->{TOKEN} = $1;
    
    } else {
        $hash->{UID} = $a[2];
    }
    
    return "Cannot define a Aqicn device. Perl modul $missingModul is missing." if ( $missingModul );
    return "too few parameters: define <name> Aqicn <OPTION-PARAMETER>" if( @a != 3 );
    return "too few parameters: define <name> Aqicn token=<TOKEN-KEY>" if( not defined($hash->{TOKEN}) and not defined($modules{Aqicn}{defptr}{TOKEN}) );
    return "too few parameters: define <name> Aqicn <STATION-UID>" if( not defined($hash->{UID}) and defined($modules{Aqicn}{defptr}{TOKEN}) );
    
    
    my $name                = $a[0];

    $hash->{VERSION}        = $version;
    $hash->{NOTIFYDEV}      = "global";
    
    
    
    
    
    if( defined($hash->{TOKEN}) ) {
        return "there is already a Aqicn Head Device, did you want to define a Aqicn station use: define <name> Aqicn <STATION-UID>" if( $modules{Aqicn}{defptr}{TOKEN} );

        $hash->{HOST}                           = 'api.waqi.info';
        $attr{$name}{room}                      = "AQICN" if( !defined( $attr{$name}{room} ) );
    
        readingsSingleUpdate ( $hash, "state", "ready", 1 );
        
        Log3 $name, 3, "Aqicn ($name) - defined Aqicn Head Device with API-Key $hash->{TOKEN}";
        $modules{Aqicn}{defptr}{TOKEN}         = $hash;

    } elsif( defined($hash->{UID}) ) {  

        $attr{$name}{room}                      = "AQICN" if( !defined( $attr{$name}{room} ) );
        $hash->{INTERVAL}                       = 3600;
        $hash->{HEADDEVICE}                     = $modules{Aqicn}{defptr}{TOKEN}->{NAME};
        
        readingsSingleUpdate ( $hash, "state", "initialized", 1 );
        
        Log3 $name, 3, "Aqicn ($name) - defined Aqicn Station Device with Station UID $hash->{UID}";
        
        $modules{Aqicn}{defptr}{UID}            = $hash;
    }

    return undef;
}

sub Aqicn_Undef($$) {

    my ( $hash, $arg )  = @_;
    
    my $name            = $hash->{NAME};


    if( defined($modules{Aqicn}{defptr}{TOKEN}) and $hash->{TOKEN} ) {
        return "there is a Aqicn Station Device present, please delete all Station Device first"
        unless( not defined($modules{Aqicn}{defptr}{UID}) );
        
        delete $modules{Aqicn}{defptr}{TOKEN};
    
    } elsif( defined($modules{Aqicn}{defptr}{UID}) and $hash->{UID} ) {
        delete $modules{Aqicn}{defptr}{UID};
    }
    
    RemoveInternalTimer( $hash );
    Log3 $name, 3, "Aqicn ($name) - Device $name deleted";

    return undef;
}

sub Aqicn_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash                                = $defs{$name};


    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "Aqicn ($name) - disabled";
        
        } elsif( $cmd eq "del" ) {
            Log3 $name, 3, "Aqicn ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
            unless($attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/);
            Log3 $name, 3, "Aqicn ($name) - disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
        
        } elsif( $cmd eq "del" ) {
            Log3 $name, 3, "Aqicn ($name) - enabled";
            readingsSingleUpdate( $hash, "state", "active", 1 );
        }
    }
    
    if( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            if( $attrVal < 30 ) {
                Log3 $name, 3, "Aqicn ($name) - interval too small, please use something >= 30 (sec), default is 300 (sec)";
                return "interval too small, please use something >= 30 (sec), default is 300 (sec)";
            
            } else {
                RemoveInternalTimer($hash);
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3, "Aqicn ($name) - set interval to $attrVal";
                Aqicn_Timer_GetData($hash);
            }
        } elsif( $cmd eq "del" ) {
            RemoveInternalTimer($hash);
            $hash->{INTERVAL} = 300;
            Log3 $name, 3, "Aqicn ($name) - set interval to default";
            Aqicn_Timer_GetData($hash);
        }
    }
    
    return undef;
}

sub Aqicn_Notify($$) {

    my ($hash,$dev) = @_;
    my $name = $hash->{NAME};
    return if (IsDisabled($name));
    
    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events = deviceEvents($dev,1);
    return if (!$events);


    Aqicn_Timer_GetData($hash) if( (grep /^INITIALIZED$/,@{$events}
                                    or grep /^DELETEATTR.$name.disable$/,@{$events}
                                    or (grep /^DEFINED.$name$/,@{$events} and $init_done))
                                    and defined($hash->{UID}) );
    return;
}

sub Aqicn_Get($$@) {
    
    my ($hash, $name, @aa)  = @_;
    my ($cmd, @args)        = @aa;


    if( $cmd eq 'update' ) {
        
        Aqicn_GetData($hash);
        return undef;
        
    } elsif( $cmd eq 'stationSearchByCity' ) {
        return "usage: $cmd" if( @args == 0 );
        
        my $city = join( " ", @args );
        my $ret;
        $ret = Aqicn_GetData($hash,$city);
        return $ret;

    } else {
    
        my $list = '';
        $list .= 'update:noArg' if( defined($hash->{UID}) );
        $list .= 'stationSearchByCity' if( defined($hash->{TOKEN}) );
        
        return "Unknown argument $cmd, choose one of $list";
    }
}

sub Aqicn_Timer_GetData($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};


    if( not IsDisabled($name) ) {
        Aqicn_GetData($hash);
        
    } else {
        readingsSingleUpdate($hash,'state','disabled',1);
    }

    InternalTimer( gettimeofday()+$hash->{INTERVAL}, 'Aqicn_Timer_GetData', $hash );
    Log3 $name, 4, "Aqicn ($name) - Call InternalTimer Aqicn_Timer_GetData";
}

sub Aqicn_GetData($;$) {

    my ($hash,$cityName)    = @_;
    
    my $name                = $hash->{NAME};
    my $host                = $modules{Aqicn}{defptr}{TOKEN}->{HOST};
    my $token               = $modules{Aqicn}{defptr}{TOKEN}->{TOKEN};
    my $uri;
    
    
    if( $hash->{UID} ) {
        my $uid     = $hash->{UID};
        $uri        = $host . '/feed/@' . $hash->{UID} . '/?token=' . $token;
    
    } else {
        $uri        = $host . '/search/?token=' . $token . '&keyword=' . urlEncode($cityName);
    }

    my $param = {
            url         => "https://".$uri,
            timeout     => 5,
            method      => 'GET',
            hash        => $hash,
            doTrigger   => 1,
            callback    => \&Aqicn_ErrorHandling,
        };
        
    $param->{cl} = $hash->{CL} if( $hash->{TOKEN} and ref($hash->{CL}) eq 'HASH' );
    
    HttpUtils_NonblockingGet($param);
    Log3 $name, 4, "Aqicn ($name) - Send with URI: https://$uri";
}

sub Aqicn_ErrorHandling($$$) {

    my ($param,$err,$data)  = @_;
    
    my $hash                = $param->{hash};
    my $name                = $hash->{NAME};


    Log3 $name, 4, "Aqicn ($name) - Recieve JSON data: $data";
    #Log3 $name, 3, "Aqicn ($name) - Recieve HTTP Code: $param->{code}";
    #Log3 $name, 3, "Aqicn ($name) - Recieve Error: $err";

    ### Begin Error Handling
    
    if( defined( $err ) ) {
        if( $err ne "" ) {
            if( $param->{cl} && $param->{cl}{canAsyncOutput} ) {
                asyncOutput( $param->{cl}, "Request Error: $err\n" );
            }

            readingsBeginUpdate( $hash );
            readingsBulkUpdate( $hash, 'state', $err, 1);
            readingsBulkUpdate( $hash, 'lastRequestError', $err, 1 );
            readingsEndUpdate( $hash, 1 );
            
            Log3 $name, 3, "Aqicn ($name) - RequestERROR: $err";
            
            $hash->{actionQueue} = [];
            return;
        }
    }

    if( $data eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
    
        readingsBeginUpdate( $hash );
        readingsBulkUpdate( $hash, 'state', $param->{code}, 1 );

        readingsBulkUpdate( $hash, 'lastRequestError', $param->{code}, 1 );

        Log3 $name, 3, "Aqicn ($name) - RequestERROR: ".$param->{code};

        readingsEndUpdate( $hash, 1 );
    
        Log3 $name, 5, "Aqicn ($name) - RequestERROR: received http code ".$param->{code}." without any data after requesting";

        $hash->{actionQueue} = [];
        return;
    }

    if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) { 
    
        readingsBeginUpdate( $hash );
        
        readingsBulkUpdate( $hash, 'state', $param->{code}, 1 );
        readingsBulkUpdate( $hash, "lastRequestError", $param->{code}, 1 );

        readingsEndUpdate( $hash, 1 );
    
        Log3 $name, 3, "Aqicn ($name) - statusRequestERROR: http error ".$param->{code};

        $hash->{actionQueue} = [];
        return;
        ### End Error Handling
    }
    
    Log3 $name, 4, "Aqicn ($name) - Recieve JSON data: $data";
    
    Aqicn_ResponseProcessing($hash,$data,$param);
}

sub Aqicn_ResponseProcessing($$$) {

    my ($hash,$json,$param) = @_;
    
    my $name                = $hash->{NAME};
    my $decode_json;
    my $readings;


    $decode_json    = eval{decode_json($json)};
    if($@){
        Log3 $name, 4, "Aqicn ($name) - error while request: $@";
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, 'JSON_Error', $@);
        readingsBulkUpdate($hash, 'httpCode', $param->{code});
        readingsBulkUpdate($hash, 'state', 'JSON error');
        readingsEndUpdate($hash,1);
        return;
    }
    
    
    #### Verarbeitung der Readings zum passenden
    if( $hash->{TOKEN} ) {
        Aqicn_ReadingsProcessing_SearchStationResponse($decode_json,$param);
        return;
    } elsif( $hash->{UID} ) {
        $readings = Aqicn_ReadingsProcessing_AqiResponse($decode_json);
    }
    
    
    Aqicn_WriteReadings($hash,$readings);
}

sub Aqicn_WriteReadings($$) {

    my ($hash,$readings)    = @_;
    
    my $name                = $hash->{NAME};
    
    
    Log3 $name, 4, "Aqicn ($name) - Write Readings";
    
    
    readingsBeginUpdate($hash);
    while( my ($r,$v) = each %{$readings} ) {
        readingsBulkUpdate($hash,$r,$v);
    }
    
    readingsBulkUpdateIfChanged($hash,'htmlStyle','<div style="background-color: '.Aqicn_HtmlStyle($readings->{'PM2.5-AQI'}).';">'.Aqicn_AirPollutionLevel($hash,$readings->{'PM2.5-AQI'}).': '.$readings->{'PM2.5-AQI'}.'</div>');
    readingsBulkUpdateIfChanged($hash,'state',Aqicn_AirPollutionLevel($hash,$readings->{'PM2.5-AQI'}));
    readingsEndUpdate($hash,1);
}

#####
#####
## my little Helper
sub Aqicn_ReadingsProcessing_SearchStationResponse($$) {
    
    my ($decode_json,$param)     = @_;
    
    
    if( $param->{cl} && $param->{cl}->{TYPE} eq 'FHEMWEB' ) {
        
        my $ret = '<html><table><tr><td>';
        $ret .= '<table class="block wide">';
        $ret .= '<tr class="even">';
        $ret .= "<td><b>City</b></td>";
        $ret .= "<td><b>Last Update Time</b></td>";
        $ret .= "<td><b>Latitude</b></td>";
        $ret .= "<td><b>Longitude</b></td>";
        $ret .= "<td></td>";
        $ret .= '</tr>';

        
        
        if( ref($decode_json->{data}) eq "ARRAY" and scalar(@{$decode_json->{data}}) > 0 ) {
            
            my $linecount=1;
            foreach my $dataset (@{$decode_json->{data}}) {
                if ( $linecount % 2 == 0 ) {
                    $ret .= '<tr class="even">';
                } else {
                    $ret .= '<tr class="odd">';
                }

                $dataset->{station}{name} =~ s/'//g;
                $ret .= "<td>".encode_utf8($dataset->{station}{name})."</td>";
                $ret .= "<td>$dataset->{'time'}{stime}</td>";
                $ret .= "<td>$dataset->{station}{geo}[0]</td>";
                $ret .= "<td>$dataset->{station}{geo}[1]</td>";
                
                
                ###### create Links
                my $aHref;
                
                # create Google Map Link
                $aHref="<a target=\"_blank\" href=\"https://www.google.de/maps/search/".$dataset->{station}{geo}[0]."+".$dataset->{station}{geo}[1]."\">Station on Google Maps</a>";
                $ret .= "<td>".$aHref."</td>";

                # create define Link
                my @headerHost = grep /Origin/, @FW_httpheader;
                $headerHost[0] =~ m/Origin:.([^\s]*)/;
                $headerHost[0] = $1;
                $aHref="<a href=\"".$headerHost[0]."/fhem?cmd=define+".makeDeviceName($dataset->{station}{name})."+Aqicn+".$dataset->{uid}.$FW_CSRF."\">Create Station Device</a>";
                $ret .= "<td>".$aHref."</td>";
                $ret .= '</tr>';
                $linecount++;
            }
        }
        
        $ret .= '</table></td></tr>';
        $ret .= '</table></html>';

        asyncOutput( $param->{cl}, $ret ) if( $param->{cl} && $param->{cl}{canAsyncOutput} );
        return;
    }
}

sub Aqicn_ReadingsProcessing_AqiResponse($) {
    
    my ($decode_json)     = @_;

    my %readings;


    $readings{'CO-AQI'} = $decode_json->{data}{iaqi}{co}{v};
    $readings{'NO2-AQI'} = $decode_json->{data}{iaqi}{no2}{v};
    $readings{'PM10-AQI'} = $decode_json->{data}{iaqi}{pm10}{v};
    $readings{'PM2.5-AQI'} = $decode_json->{data}{iaqi}{pm25}{v};
    $readings{'temperature'} = $decode_json->{data}{iaqi}{t}{v};
    $readings{'pressure'} = $decode_json->{data}{iaqi}{p}{v};
    $readings{'humidity'} = $decode_json->{data}{iaqi}{h}{v};
    $readings{'status'} = $decode_json->{status};
    $readings{'pubDate'} = $decode_json->{data}{time}{s};
    
    return \%readings;
}

sub Aqicn_AirPollutionLevel($$) {

    my ($hash,$aqi)     = @_;
    my $name            = $hash->{NAME};
    my $apl;


    if($aqi < 51)       { $apl = 1}
    elsif($aqi < 101)   { $apl = 2}
    elsif($aqi < 151)   { $apl = 3}
    elsif($aqi < 201)   { $apl = 4}
    elsif($aqi < 301)   { $apl = 5}
    else                { $apl = 6}


    if( (AttrVal('global','language','none') eq 'DE' or AttrVal($name,'language','none') eq 'de') and AttrVal($name,'language','none') ne 'en' ) {
        return Aqicn_i18n_de($apl);
    } else {
        return Aqicn_i18n_en($apl);
    }
}

sub Aqicn_HtmlStyle($) {

    my $aqi         = shift;
    my $bgColor;


    if($aqi < 51)       { $bgColor = '#009966'}
    elsif($aqi < 101)   { $bgColor = '#ffde33'}
    elsif($aqi < 151)   { $bgColor = '#ff9933'}
    elsif($aqi < 201)   { $bgColor = '#cc0033'}
    elsif($aqi < 301)   { $bgColor = '#660099'}
    else                { $bgColor = '#7e0023'}

    return $bgColor;
}

sub Aqicn_i18n_de($) {

    my $value = shift;
    
    
    my %i18nde = (
                    1   => 'Gut',
                    2   => 'Moderat',
                    3   => 'Ungesund für empfindliche Personengruppen',
                    4   => 'Ungesund',
                    5   => 'Sehr ungesund',
                    6   => 'Gefährlich'
    );
    
    return $i18nde{$value};
}

sub Aqicn_i18n_en($) {

    my $value = shift;
    
    
    my %i18nen = (
                    1   => 'Good',
                    2   => 'Moderate',
                    3   => 'Unhealthy for Sensitive Groups',
                    4   => 'Unhealthy',
                    5   => 'Very Unhealthy',
                    6   => 'Hazardous'
    );
    
    return $i18nen{$value};
}





1;


=pod

=item device
=item summary
=item summary_DE

=begin html

<a name="Aqicn"></a>
<h3></h3>
<ul>

</ul>

=end html
=begin html_DE

<a name="Aqicn"></a>
<h3></h3>

=end html_DE
=cut
