###############################################################################
#
# Developed with eclipse
#
#  (c) 2019 Copyright: J.K. (J0EK3R at gmx dot net)
#  All rights reserved
#
#   Special thanks goes to committers:
#
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
# $Id: 73_Map.pm 201 2020-04-04 06:14:00Z J0EK3R $
#
###############################################################################

package main;

my $VERSION = "0.0.1";

use strict;
use warnings;

my $missingModul = "";

use FHEM::Meta;

#########################
# Forward declaration
sub Map_Initialize($);
sub Map_Define($$);
sub Map_Undef($$);
sub Map_Delete($$);
sub Map_Rename(@);
sub Map_Attr(@);
sub Map_Notify($$);
sub Map_Set($@);
sub Map_Write($$);

sub Map_UpdateInternals($);

my $DebugMarker         = "Dbg";

#####################################
# Map_Initialize( $hash )
sub Map_Initialize($)
{
  my ( $hash ) = @_;

  $hash->{DefFn}    = \&Map_Define;
  $hash->{UndefFn}  = \&Map_Undef;
  $hash->{DeleteFn} = \&Map_Delete;
  $hash->{RenameFn} = \&Map_Rename;
  $hash->{AttrFn}   = \&Map_Attr;
  $hash->{NotifyFn} = \&Map_Notify;
  $hash->{SetFn}    = \&Map_Set;
  $hash->{WriteFn}  = \&Map_Write;

  $hash->{AttrList} = 
    "debug:0,1 " . 
    "disable:0,1 " . 
    $readingFnAttributes;

  foreach my $d ( sort keys %{ $modules{Map}{defptr} } )
  {
    my $hash = $modules{Map}{defptr}{$d};
    $hash->{VERSION} = $VERSION;
  }

  return FHEM::Meta::InitMod( __FILE__, $hash );
}

#####################################
# Map_Define( $hash, $def )
sub Map_Define($$)
{
  my ( $hash, $def ) = @_;

  my @a = split( "[ \t][ \t]*", $def );

  return $@
    unless ( FHEM::Meta::SetInternals($hash) );

  return "wrong number of parameters: define <NAME> Map"
    if ( @a != 2 );

  return "Cannot define Map. Perl modul " . ${missingModul} . " is missing."
    if ($missingModul);

  my $name = $a[0];
  $hash->{VERSION}                        = $VERSION;
  $hash->{NOTIFYDEV}                      = "global,$name";

  $hash->{helper}{DEBUG}                  = "0";
  $hash->{helper}{IsDisabled}             = "0";
  $hash->{helper}{GenericReadings}        = "none";
  
  # set default Attributes
  if (AttrVal($name, "room", "none" ) eq "none")
  {
    CommandAttr(undef, $name . " room Maps");
  }

  readingsSingleUpdate( $hash, "state", "initialized", 1 );

  Log3($name, 3, "Map_Define($name) - defined Map");

  #$modules{Map}{defptr}{ACCOUNT} = $hash;

  return undef;
}

#####################################
# Map_Undef( $hash, $name )
sub Map_Undef($$)
{
  my ( $hash, $name ) = @_;

  return undef;
}

#####################################
# Map_Delete( $hash, $name )
sub Map_Delete($$)
{
  my ( $hash, $name ) = @_;

  return undef;
}

#####################################
# Map_Rename( $new, $old )
sub Map_Rename(@)
{
  my ( $new, $old ) = @_;
  my $hash = $defs{$new};

  return undef;
}

#####################################
# Map_Attr($cmd, $name, $attrName, $attrVal)
sub Map_Attr(@)
{
  my ( $cmd, $name, $attrName, $attrVal ) = @_;
  my $hash = $defs{$name};

  Log3($name, 4, "Map_Attr($name) - AttrName \"$attrName\" : \"$attrVal\"");

  # Attribute "disable"
  if ( $attrName eq "disable" )
  {
    if ( $cmd eq "set" and 
      $attrVal eq "1" )
    {
      Log3($name, 3, "Map_Attr($name) - disabled");

      $hash->{helper}{IsDisabled} = "1";
      
      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, "state", "inactive", 1 );
      readingsEndUpdate( $hash, 1 );
    } 
    else
    {
      Log3($name, 3, "Map_Attr($name) - enabled");

      $hash->{helper}{IsDisabled} = "0";

      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, "state", "active", 1 );
      readingsEndUpdate( $hash, 1 );
    }
  }

  # Attribute "debug"
  elsif ( $attrName eq "debug" )
  {
    if ( $cmd eq "set")
    {
      Log3($name, 3, "Map_Attr($name) - debugging enabled");

      $hash->{helper}{DEBUG} = "$attrVal";
      Map_UpdateInternals($hash);
    } 
    elsif ( $cmd eq "del" )
    {
      Log3($name, 3, "Map_Attr($name) - debugging disabled");

      $hash->{helper}{DEBUG} = "0";
      Map_UpdateInternals($hash);
    }
  }

  return undef;
}

#####################################
# Map_Notify( $hash, $dev )
sub Map_Notify($$)
{
  my ( $hash, $dev ) = @_;
  my $name = $hash->{NAME};

  return
    if ($hash->{helper}{IsDisabled} ne "0");

  my $devname = $dev->{NAME};
  my $devtype = $dev->{TYPE};
  my $events  = deviceEvents( $dev, 1 );

  return
    if (!$events);

  Log3($name, 4, "Map_Notify($name) - DevType: \"$devtype\"");

  # process "global" events
  if ($devtype eq "Global")
  { 
    if (grep(m/^INITIALIZED$/, @{$events}))
    {
      # this is the initial call after fhem has startet
      Log3($name, 3, "Map_Notify($name) - INITIALIZED");
    }

    elsif (grep(m/^REREADCFG$/, @{$events}))
    {
      Log3($name, 3, "Map_Notify($name) - REREADCFG");
    }

    elsif (grep(m/^DEFINED.$name$/, @{$events}) )
    {
      Log3($name, 3, "Map_Notify($name) - DEFINED");
    }

    elsif (grep(m/^MODIFIED.$name$/, @{$events}))
    {
      Log3($name, 3, "Map_Notify($name) - MODIFIED");
    }

    if ($init_done)
    {
    }
  }
  
  # process internal events
  elsif ($devtype eq "Map") 
  {
  }
  
  return;
}

#####################################
# Map_Set( $hash, $name, $cmd, @args )
sub Map_Set($@)
{
  my ( $hash, $name, $cmd, @args ) = @_;

  Log3($name, 4, "Map_Set($name) - Set was called cmd: >>$cmd<<");

  ### Command "clearreadings"
  if ( lc $cmd eq lc "clearreadings" )
  {
    return "usage: $cmd <mask>"
      if ( @args != 1 );

    my $mask = $args[0];
    fhem("deletereading $name $mask", 1);
    return;
  }
  ### Command "debugGetDevicesState"
  else
  {
    my $list = "";

    $list .= "clearreadings:$DebugMarker.*,.* ";

    return "Unknown argument $cmd, choose one of $list";
  }
  return undef;
}

#####################################
# Map_Write( $hash, $param )
sub Map_Write($$)
{
  my ( $hash, $param ) = @_;
  my $name = $hash->{NAME};
  my $resultCallback = $param->{resultCallback};

  Log3($name, 4, "Map_Write($name)");
}

#####################################
# Map_UpdateInternals( $hash )
sub Map_UpdateInternals($)
{
  my ($hash)  = @_;
  my $name    = $hash->{NAME};

  Log3($name, 5, "Map_UpdateInternals($name)");
  
  if($hash->{helper}{DEBUG} eq "1")
  {
    $hash->{DEBUG_IsDisabled}               = $hash->{helper}{IsDisabled};
  }
  else
  {
    # delete all keys starting with "DEBUG_"
    my @matching_keys =  grep /DEBUG_/, keys %$hash;
    foreach (@matching_keys)
    {
      delete $hash->{$_};
    }
  }
}



=pod
=item device
=item summary module to communicate with the GroheOndusCloud
=begin html

  <a name="Map"></a><h3>Map</h3>
  <ul>
    In combination with the FHEM module <a href="#GroheOndusSmartDevice">GroheOndusSmartDevice</a> this module communicates with the <b>Grohe-Cloud</b>.<br>
    <br>
    You can get the configurations and measured values of the registered <b>Sense</b> und <b>SenseGuard</b> appliances 
    and i.E. open/close the valve of a <b>SenseGuard</b> appliance.<br>
    <br>
    Once the <b>Map</b> is created the connected devices are recognized and created automatically in FHEM.<br>
    From now on the devices can be controlled and changes in the <b>GroheOndusAPP</b> are synchronized with the state and readings of the devices.
    <br>
    <br>
    <b>Notes</b>
    <ul>
      <li>This module communicates with the <b>Grohe-Cloud</b> - you have to be registered.
      </li>
      <li>Register your account directly at grohe - don't use "Sign in with Apple/Google/Facebook" or something else.
      </li>
      <li>There is a <b>debug-mode</b> you can enable/disable with the <b>attribute debug</b> to see more internals.
      </li>
    </ul>
    <br>
    <a name="Map"></a><b>Define</b>
    <ul>
      <code><B>define &lt;name&gt; Map</B></code>
      <br><br>
      Example:<br>
      <ul>
        <code>
        define Fordpass.Account Map<br>
        <br>
        </code>
      </ul>
    </ul><br>
    <a name="Map"></a><b>Set</b>
    <ul>
      <li><a name="MapgroheOndusAccountPassword">groheOndusAccountPassword</a><br>
        Set the password and store it.
      </li>
      <br>
      <li><a name="MapdeletePassword">deletePassword</a><br>
        Delete the password from store.
      </li>
      <br>
      <li><a name="Mapupdate">update</a><br>
        Login if needed and update all locations, rooms and appliances.
      </li>
      <br>
      <li><a name="Mapclearreadings">clearreadings</a><br>
        Clear all readings of the module.
      </li>
      <br>
      <b><i>Debug-mode</i></b><br>
      <br>
      <li><a name="MapdebugGetDevicesState">debugGetDevicesState</a><br>
        If debug-mode is enabled:<br>
        get locations, rooms and appliances.
      </li>
      <br>
      <li><a name="MapdebugLogin">debugLogin</a><br>
        If debug-mode is enabled:<br>
        login.
      </li>
      <br>
      <li><a name="MapdebugSetLoginState">debugSetLoginState</a><br>
        If debug-mode is enabled:<br>
        set/reset internal statemachine to/from state "login" - if set all actions will be locked!.
      </li>
      <br>
      <li><a name="MapdebugSetTokenExpired">debugSetTokenExpired</a><br>
        If debug-mode is enabled:<br>
        set the expiration timestamp of the login-token to now - next action will trigger a login.
      </li>
    </ul>
    <br>
    <a name="Mapattr"></a><b>Attributes</b><br>
    <ul>
      <li><a name="Mapusername">username</a><br>
        Your registered Email-address to login to the grohe clound.
      </li>
      <br>
      <li><a name="Mapautocreatedevices">autocreatedevices</a><br>
        If <b>enabled</b> (default) then GroheOndusSmartDevices will be created automatically.<br>
        If <b>disabled</b> then GroheOndusSmartDevices must be create manually.<br>
      </li>
      <br>
      <li><a name="Mapinterval">interval</a><br>
        Interval in seconds to poll for locations, rooms and appliances.
        The default value is 60 seconds.
      </li>
      <br>
      <li><a name="Mapdisable">disable</a><br>
        If <b>0</b> (default) then Map is <b>enabled</b>.<br>
        If <b>1</b> then Map is <b>disabled</b> - no communication to the grohe cloud will be done.<br>
      </li>
      <br>
      <li><a name="Mapdebug">debug</a><br>
        If <b>0</b> (default) debugging mode is <b>disabled</b>.<br>
        If <b>1</b> debugging mode is <b>enabled</b> - more internals and commands are shown.<br>
      </li>
      <br>
      <li><a name="MapdebugJSON">debugJSON</a><br>
        If <b>0</b> (default)<br>
        If <b>1</b> if communication fails the json-payload of incoming telegrams is set to a reading.<br>
      </li>
    </ul><br>
    <a name="Mapreadings"></a><b>Readings</b>
    <ul>
      <li><a>count_appliance</a><br>
        Count of appliances.<br>
      </li>
      <br>
      <li><a>count_locations</a><br>
        Count of locations.<br>
      </li>
      <br>
      <li><a>count_rooms</a><br>
        Count of rooms.<br>
      </li>
    </ul><br>
    <a name="Mapinternals"></a><b>Internals</b>
    <ul>
      <li><a>DEBUG_IsDisabled</a><br>
        If <b>1</b> (default)<br>
        If <b>0</b> debugging mode is enabled - more internals and commands are shown.<br>
      </li>
    </ul><br>
    <br>
  </ul>
=end html

=for :application/json;q=META.json 73_Map.pm
{
  "abstract": "Modul to communicate with the GroheCloud",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Datenübertragung zur GroheCloud"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Grohe",
    "Smart"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "author": [
    "J0EK3R <J0EK3R@gmx.net>"
  ],
  "x_fhem_maintainer": [
    "J0EK3R"
  ],
  "x_fhem_maintainer_github": [
    "J0EK3R@gmx.net"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 0,
        "HTML::Entities": 0,
        "JSON": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut
