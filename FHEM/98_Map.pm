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

my $VERSION = "0.0.6";

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

sub Map_UpdateInternals($);
sub Map_UpdateLocation($);
sub Map_CreateURL($);
sub Map_FwFn($$$$);
sub Map_UpdateMap($);
sub Map_doUpdateMap($;$);

sub Map_Store($$$$);
sub Map_Restore($$$$);
sub Map_StoreRename($$$$);

my $ReadingsDebugMarker               = "Dbg";
my $DefaultMode                       = "source";

my $DefaultIcon                       = "4";
my $DefaultZoom                       = "15";
my $DefaultInterval_s                 = "5";
my $DefaultFrameWidth                 = "100%";
my $DefaultFrameHeight                = "800";
my $DefaultFrameShowDetailLinkInGroup = "1";
my $DefaultMapProvider                = "osmtools";

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
  
  $hash->{FW_summaryFn} = \&Map_FwFn;
  $hash->{FW_detailFn}  = \&Map_FwFn;
  $hash->{FW_atPageEnd} = 1;
  
  $data{FWEXT}{"/Map_UpdateMap"}{FUNC} = "Map_UpdateMap";
  $data{FWEXT}{"/Map_UpdateMap"}{FORKABLE} = 1;

  $hash->{AttrList} = 
    "debug:0,1 " . 
    "mode:$DefaultMode,simulation,off " . 
    "mapProvider:osmtools " . 
    "sourceDeviceName " . 
    "sourceReadingNameLatitude " . 
    "sourceReadingNameLongitude " . 
    "refreshInterval " . 
    "frameWidth " . 
    "frameHeight " . 
    "frameShowDetailLinkInGroup:1,0 " . 
    "pinIcon:0,1,4,5,6,7,8,9,10,11 " . 
    "zoom:0,1,2,3,4,5,6,7,8,9,10,11,14,15,16,17,18,19 " . 
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
  
  my $id = $hash->{FUUID};
  $id =~ s/[^a-zA-Z0-9,]//g;
  
  $hash->{VERSION}                        = $VERSION;
  $hash->{NOTIFYDEV}                      = "global,$name";
  
  $hash->{helper}{ID}                         = $id;
  $hash->{helper}{DEBUG}                      = "0";
  $hash->{helper}{IsDisabled}                 = "0";
  $hash->{helper}{Mode}                       = $DefaultMode;
  $hash->{helper}{SourceDeviceName}           = "global";
  $hash->{helper}{SourceReadingNameLatitude}  = "latitude";
  $hash->{helper}{SourceReadingNameLongitude} = "longitude";

  $hash->{helper}{MapProvider}                = "OpenStreeMap";
  $hash->{helper}{Latitude}                   = "52.516275";
  $hash->{helper}{Longitude}                  = "13.377704";
  $hash->{helper}{Icon}                       = $DefaultIcon;
  $hash->{helper}{Zoom}                       = $DefaultZoom;
  $hash->{helper}{FrameWidth}                 = $DefaultFrameWidth;
  $hash->{helper}{FrameHeight}                = $DefaultFrameHeight;
  $hash->{helper}{FrameShowDetailLinkInGroup} = $DefaultFrameShowDetailLinkInGroup;
  $hash->{helper}{RefreshInterval}            = $DefaultInterval_s;
  $hash->{helper}{Url}                        = "";

  $hash->{helper}{Longitude}                  = Map_Restore( $hash, "MAP_Define", "Longitude", $hash->{helper}{Longitude});
  $hash->{helper}{Latitude}                   = Map_Restore( $hash, "Map_Define", "Latitude", $hash->{helper}{Latitude});

  if(Map_Restore( $hash, "MAP_Define", "FirstDefine", $id) eq $id)
  {
    # set default Attributes
    if (AttrVal($name, "room", "none" ) eq "none")
    {
      CommandAttr(undef, $name . " room Maps");
    }

    if (AttrVal($name, "event-on-change-reading", "none" ) eq "none")
    {
      CommandAttr(undef, $name . " event-on-change-reading .*");
    }
  }
  Map_Store($hash, "MAP_Define", "FirstDefine", "False");

  readingsSingleUpdate( $hash, "state", "initialized", 1 );

  Log3($name, 3, "Map_Define($name) - defined Map");

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

  Log3($name, 4, "Map_Delete($name)");

  # delete all stored values
  Map_Store($hash, "Map_Delete", "FirstDefine", undef);
  Map_Store($hash, "Map_Delete", "Latitude", undef);
  Map_Store($hash, "Map_Delete", "Longitude", undef);

  return undef;
}

#####################################
# Map_Rename( $new, $old )
sub Map_Rename(@)
{
  my ($new_name, $old_name) = @_;
  my $hash = $defs{$new_name};
  my $name = $hash->{NAME};

  Log3($name, 4, "Map_Rename($name)");

  # rename all stored values
  Map_StoreRename($hash, "Map_Rename", $old_name, "FirstDefine");
  Map_StoreRename($hash, "Map_Rename", $old_name, "Latitude");
  Map_StoreRename($hash, "Map_Rename", $old_name, "Longitude");

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
  if (lc $attrName eq lc "disable" )
  {
    if ( $cmd eq "set" and 
      $attrVal eq "1" )
    {
      $hash->{helper}{IsDisabled} = "1";
      
      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, "state", "inactive", 1 );
      readingsEndUpdate( $hash, 1 );
    } 
    else
    {
      $hash->{helper}{IsDisabled} = "0";

      readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, "state", "active", 1 );
      readingsEndUpdate( $hash, 1 );
    }
    Log3($name, 3, "Map_Attr($name) - disabled $hash->{helper}{IsDisabled}");

    Map_UpdateInternals($hash);
  }

  # Attribute "debug"
  elsif (lc $attrName eq lc "debug" )
  {
    if ( $cmd eq "set")
    {
      $hash->{helper}{DEBUG} = "$attrVal";
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{DEBUG} = "0";
    }
    Log3($name, 3, "Map_Attr($name) - debug $hash->{helper}{DEBUG}");

    Map_UpdateInternals($hash);
  }
  
  # Attribute "mode"
  elsif (lc $attrName eq lc "mode" )
  {
    if ( $cmd eq "set")
    {
      $hash->{helper}{Mode} = "$attrVal";
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{Mode} = $DefaultMode;
    }
    Log3($name, 3, "Map_Attr($name) - mode $hash->{helper}{Mode}");

    Map_UpdateInternals($hash);
  }
  
  # Attribute "pinIcon"
  elsif (lc $attrName eq lc "pinIcon" )
  {
    if ( $cmd eq "set")
    {
      $hash->{helper}{Icon} = "$attrVal";
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{Icon} = $DefaultIcon;
    }
    Log3($name, 3, "Map_Attr($name) - pinIcon $hash->{helper}{Icon}");

    Map_UpdateInternals($hash);
  }
  
  # Attribute "frameWidth"
  elsif (lc $attrName eq lc "frameWidth" )
  {
    if ( $cmd eq "set")
    {
      $hash->{helper}{FrameWidth} = "$attrVal";
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{FrameWidth} = $DefaultFrameWidth;
    }
    Log3($name, 3, "Map_Attr($name) - frameWidth $hash->{helper}{FrameWidth}");

    Map_UpdateInternals($hash);
  }
  
  # Attribute "frameHeight"
  elsif (lc $attrName eq lc "frameHeight" )
  {
    if ( $cmd eq "set")
    {
      $hash->{helper}{FrameHeight} = "$attrVal";
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{FrameHeight} = $DefaultFrameHeight;
    }
    Log3($name, 3, "Map_Attr($name) - frameHeight $hash->{helper}{FrameHeight}");

    Map_UpdateInternals($hash);
  }

  # Attribute "frameShowDetailLinkInGroup"
  elsif (lc $attrName eq lc "frameShowDetailLinkInGroup" )
  {
    if ( $cmd eq "set")
    {
      $hash->{helper}{FrameShowDetailLinkInGroup} = "$attrVal";
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{FrameShowDetailLinkInGroup} = $DefaultFrameShowDetailLinkInGroup;
    }
    Log3($name, 3, "Map_Attr($name) - frameWidth $hash->{helper}{FrameShowDetailLinkInGroup}");

    Map_UpdateInternals($hash);
  }
  
  # Attribute "zoom"
  elsif (lc $attrName eq lc "zoom" )
  {
    if ( $cmd eq "set")
    {
      $hash->{helper}{Zoom} = "$attrVal";
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{Zoom} = $DefaultZoom;
    }
    Log3($name, 3, "Map_Attr($name) - zoom $hash->{helper}{Zoom}");

    Map_UpdateInternals($hash);
  }
  
  # Attribute "mapProvider"
  elsif (lc $attrName eq lc "mapProvider" )
  {
    if ( $cmd eq "set")
    {
      $hash->{helper}{MapProvider} = "$attrVal";
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{MapProvider} = $DefaultMapProvider;
    }
    Log3($name, 3, "Map_Attr($name) - mapProvider $hash->{helper}{MapProvider}");

    Map_UpdateInternals($hash);
  }
  
  # Attribute "refreshInterval"
  elsif (lc $attrName eq lc "refreshInterval" )
  {
    if ( $cmd eq "set")
    {
      return "Interval must be greater than 0"
        unless($attrVal > 0);

      $hash->{helper}{RefreshInterval} = "$attrVal";
    } 
    elsif ( $cmd eq "del" )
    {
      $hash->{helper}{RefreshInterval} = $DefaultInterval_s;
    }
    Log3($name, 3, "Map_Attr($name) - refreshInterval $hash->{helper}{RefreshInterval}");

    Map_UpdateInternals($hash);
  }
  
  # Attribute "sourceDeviceName"
  elsif(lc $attrName eq lc "sourceDeviceName")
  {
    if($cmd eq "set")
    {
      $hash->{helper}{SourceDeviceName} = "$attrVal";
    } 
    else
    {
      $hash->{helper}{SourceDeviceName} = "";
    }
    Log3($name, 3, "Map_Attr($name) - set sourceDeviceName: $hash->{helper}{SourceDeviceName}");

    Map_UpdateInternals($hash);
  }

  # Attribute "sourceReadingNameLatitude"
  elsif(lc $attrName eq lc "sourceReadingNameLatitude")
  {
    if($cmd eq "set")
    {
      $hash->{helper}{SourceReadingNameLatitude} = "$attrVal";
    } 
    else
    {
      $hash->{helper}{SourceReadingNameLatitude} = "";
    }
    Log3($name, 3, "Map_Attr($name) - set sourceReadingNameLatitude: $hash->{helper}{SourceReadingNameLatitude}");

    Map_UpdateInternals($hash);
  }

  # Attribute "sourceReadingNameLongitude"
  elsif(lc $attrName eq lc "sourceReadingNameLongitude")
  {
    if($cmd eq "set")
    {
      $hash->{helper}{SourceReadingNameLongitude} = "$attrVal";
    } 
    else
    {
      $hash->{helper}{SourceReadingNameLongitude} = "";
    }
    Log3($name, 3, "Map_Attr($name) - set sourceReadingNameLongitude: $hash->{helper}{SourceReadingNameLongitude}");

    Map_UpdateInternals($hash);
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
  ### Command "latitude"
  elsif( lc $cmd eq lc "latitude" )
  {
    $hash->{helper}{Latitude} = join( " ", @args );
    Map_UpdateLocation($hash);
    return;
  }
  ### Command "longitude"
  elsif( lc $cmd eq lc "longitude" )
  {
    $hash->{helper}{Longitude} = join( " ", @args );
    Map_UpdateLocation($hash);
    return;
  }
  ### create Command list
  else
  {
    my $list = "";

    $list .= "latitude ";
    $list .= "longitude ";
    $list .= "clearreadings:$ReadingsDebugMarker.*,.* ";

    return "Unknown argument $cmd, choose one of $list";
  }
}

#####################################
# Map_UpdateInternals( $hash )
sub Map_UpdateInternals($)
{
  my ($hash)  = @_;
  my $name    = $hash->{NAME};

  Log3($name, 3, "Map_UpdateInternals($name)");
  
  if($hash->{helper}{DEBUG} eq "1")
  {
    $hash->{DEBUG_IsDisabled}                       = $hash->{helper}{IsDisabled};

    $hash->{DEBUG_ID}                               = $hash->{helper}{ID};
    $hash->{DEBUG_Mode}                             = $hash->{helper}{Mode};
    $hash->{DEBUG_SourceDeviceName}                 = $hash->{helper}{SourceDeviceName};
    $hash->{DEBUG_SourceSourceReadingNameLatitude}  = $hash->{helper}{SourceReadingNameLatitude};
    $hash->{DEBUG_SourceReadingNameLongitude}       = $hash->{helper}{SourceReadingNameLongitude};

    $hash->{DEBUG_MapProvider}                      = $hash->{helper}{MapProvider};
    $hash->{DEBUG_Latitude}                         = $hash->{helper}{Latitude};
    $hash->{DEBUG_Longitude}                        = $hash->{helper}{Longitude};
    $hash->{DEBUG_Icon}                             = $hash->{helper}{Icon};
    $hash->{DEBUG_Zoom}                             = $hash->{helper}{Zoom};
    $hash->{DEBUG_FrameWidth}                       = $hash->{helper}{FrameWidth};
    $hash->{DEBUG_FrameHeight}                      = $hash->{helper}{FrameHeight};
    $hash->{DEBUG_FrameShowDetailLinkInGroup}       = $hash->{helper}{FrameShowDetailLinkInGroup};
    $hash->{DEBUG_RefreshInterval}                  = $hash->{helper}{RefreshInterval};
    $hash->{DEBUG_Url}                              = $hash->{helper}{Url};
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

#####################################
# Map_UpdateLocation( $hash )
sub Map_UpdateLocation($)
{
  my ($hash)  = @_;
  my $name    = $hash->{NAME};

  Log3($name, 5, "Map_UpdateLocation($name)");
  
  # Change latitude and longitude to get a new location if no sourcedevice is defined for debugging
  my $longitude         = $hash->{helper}{Longitude};
  my $latitude          = $hash->{helper}{Latitude};
  my $sourceDeviceName  = $hash->{helper}{SourceDeviceName};
  
  my $savedLongitude = $longitude;
  my $savedLatitude = $latitude;
  
  # mode is "source" 
  if($hash->{helper}{Mode} eq $DefaultMode)
  {
    # get readings from sourcedevice
    if(defined($defs{$sourceDeviceName}))
    {
      $longitude  = ReadingsVal($sourceDeviceName, $hash->{helper}{SourceReadingNameLongitude}, $longitude);
      $latitude   = ReadingsVal($sourceDeviceName, $hash->{helper}{SourceReadingNameLatitude}, $latitude);
    }
  }
  # if mode is simulation
  elsif($hash->{helper}{Mode} eq "simulation")
  {
    $longitude  += 0.001;
    $latitude   += 0.001;
  }
  # mode is "off"
  else
  {
  }

  # position has changed?  
  if($savedLatitude ne $latitude or
    $savedLongitude ne $longitude)
  {
    $hash->{helper}{Latitude}   = $latitude;
    $hash->{helper}{Longitude}  = $longitude;
    Map_UpdateInternals($hash);

    Map_Store($hash, "Map_UpdateLocation", "Latitude", $hash->{helper}{Latitude});
    Map_Store($hash, "Map_UpdateLocation", "Longitude", $hash->{helper}{Longitude});
  }

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "latitude", "$latitude");
  readingsBulkUpdate($hash, "longitude", "$longitude");
  readingsEndUpdate($hash, 1);
}

#####################################
# Map_CreateURL( $hash )
sub Map_CreateURL($)
{
  my ($hash)  = @_;
  my $name    = $hash->{NAME};

  Log3($name, 5, "Map_CreateURL($name)");
  
  my $longitude = $hash->{helper}{Longitude};
  my $latitude  = $hash->{helper}{Latitude};

   my $url = ""; 

   if($hash->{helper}{MapProvider} eq "googlemapsXXX")
   {
#     $url = "https://maps.google.de/maps/search/?api=1" .
#       "&query=$latitude,$longitude";
     $url = "https://maps.google.de/maps/embed/v1/place/?api=1" .
       "&map_action=map" .
       "&zoom=$hash->{helper}{Zoom}" .
       "&basemap=terrain" .
       "&center=$latitude%2$longitude" .
       "";
   }
   elsif($hash->{helper}{MapProvider} eq "openstreetmap")
   {
     $url = "http://www.openstreetmap.org/?" .
       "mlat=$latitude" .
       "&mlon=$longitude" .
       "#map=$hash->{helper}{Zoom}/$latitude/$longitude" .
       "";
   }
   # default: ($hash->{helper}{MapProvider} eq "osmtools")
   else 
   {
     $url = "http://m.osmtools.de/?" .
       "zoom=$hash->{helper}{Zoom}" . 
       "&lon=$longitude" . 
       "&mlon=$longitude" .
       "&lat=$latitude" . 
       "&mlat=$latitude" .
       "&icon=$hash->{helper}{Icon}" .
       "&iframe=1" .
       "";
   }

  $hash->{helper}{Url} = $url;
  Map_UpdateInternals($hash);

  return $url;
}

##################
# Map_FwFn($$$$)1
sub Map_FwFn($$$$)
{
  my ($FW_wname, $name, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$name};
  my $ret = "";
  
  my $id = $hash->{helper}{ID};

  my $isFirst = (!$pageHash || !$pageHash->{mapLoaded});

  $isFirst = 0 
    if($pageHash && 
      $pageHash->{mapIdx} && 
      $pageHash->{mapIdx} != 1);

  $pageHash->{mapLoaded} = 1
    if($pageHash);

#  $ret .= "<script type='text/javascript' src='$FW_ME/pgm2/svg.js'></script>"
#    if($isFirst);

  # plots navigation buttons
  if($isFirst) 
  {
#    $ret .= '<div class="SVGlabel" data-name="svgZoomControl">';
#    $ret .= Map_zoomLink("zoom=-1", "Zoom-in", "zoom in");
#    $ret .= Map_zoomLink("zoom=1",  "Zoom-out","zoom out");
#    $ret .= SVG_zoomLink("off=-1",  "Prev",    "prev");
#    $ret .= SVG_zoomLink("off=1",   "Next",    "next");
#    $ret .= '</div>';
#    $pageHash->{buttons} = 1 
#      if($pageHash);

#    $ret .= "<br>";
  }

  $ret .= "<div class=\"Map Map_$name\">\n";

  my $scriptSrc = "$FW_ME/Map_UpdateMap?dev=$name";
  my $url = Map_CreateURL($hash);
  my $height = $hash->{helper}{FrameHeight};
  my $width = $hash->{helper}{FrameWidth};
  
  my $scriptFrameIdentifier = "Script_Frame_$name";
  my $mapFrameIdentifier = "Map_Frame_$name";

  my $refreshInterval_ms = $hash->{helper}{RefreshInterval} * 1000;

  # by setting this hidden iframe's src the script to uptate is loaded from fhem 
  my $scriptFrame = 
    "<iframe " .
    "id='$scriptFrameIdentifier' " .
#    "src='$scriptSrc' " .
    # hidden
    "width='0' " .
    "height='0' ".
    "frameborder='0' " .
    "></iframe>\n";

  # this iframe contains the embedded iframe from the map-provider (OpenStreetMap)
  my $mapFrame = 
    "<iframe " .
    "id='$mapFrameIdentifier' " .
    "width='$width' " .
    "height='$height' ".
    "frameborder='0' " .
    "scrolling='no' " .
    "marginheight='0' " .
    "marginwidth='0' " .
    "src='$url' " .
    "></iframe>\n";

  # this script contains global variables
  # this variables will be changed by the update-script
  my $script = 
    "<script type='module'> " .
      # global variables
      "window.scriptFrame_" . $id . " = document.getElementById('$scriptFrameIdentifier'); " .
      "window.mapFrame_" . $id . " = document.getElementById('$mapFrameIdentifier'); " .
      "window.url_" . $id . " = '$url'; " .
      "window.refreshInterval_ms_" . $id . " = $refreshInterval_ms; " .
      "window.frameheight_" . $id . " = '$height'; " .
      "window.framewidth_" . $id . " = '$width'; " .
    "</script>\n" .
    
    # this script will install the cyclic called update-function
    "<script type='text/javascript'> " .
      # start timer
      "window.setTimeout('updateIFrame_" . $id . "();', window.refreshInterval_ms_" . $id . "); " .

      # 
      "function updateIFrame_" . $id . "() " . 
      "{ " .
        # call script by setting the src of the iframe
        "window.scriptFrame_" . $id . ".src='$scriptSrc'; " .
        
        # start timer again with global-variable value
        "window.setTimeout('updateIFrame_" . $id . "();', window.refreshInterval_ms_" . $id . "); " .
    
        "window.mapFrame_" . $id . ".height = window.frameheight_" . $id . "; " .
        "window.mapFrame_" . $id . ".width = window.framewidth_" . $id . "; " .
    
        # only set source if needed
        "if(window.mapFrame_" . $id . ".src != window.url_" . $id . ")" .
        "{ " .
          "window.mapFrame_" . $id . ".src = window.url_" . $id . "; " .
        "} " .
      "} " .
    "</script>\n";

  $ret .= $scriptFrame;
  $ret .= $mapFrame;
  $ret .= $script;

  $ret .= "</div>\n";

  if(!$pageHash) 
  {
#      $ret .= SVG_PEdit($FW_wname,$d,$room,$pageHash) . "<br>";
      $ret .= "<br>";
  }
  else 
  {
    if((!AttrVal($name, "group", "") && 
      !$FW_subdir) ||
      $hash->{helper}{FrameShowDetailLinkInGroup} eq "1") 
    {
      my $alias = AttrVal($name, "alias", $name);
      my $clAdd = "\" data-name=\"$name";
      $clAdd .= "\" style=\"display:none;"
        if($FW_hiddenroom{detail});
      $ret .= FW_pH("detail=$name", $alias, 0, "Maplabel Map_$name $clAdd", 1, 0);
      $ret .= "<br>";
    }
  }

  return $ret;
}

######################
# Map_UpdateMap($)
sub Map_UpdateMap($)
{
  return Map_doUpdateMap($FW_webArgs{dev});
}

######################
# Map_doUpdateMap($)
sub Map_doUpdateMap($;$)
{
  my ($name, $noHeader) = @_;
  my $hash = $defs{$name};
  my $id = $hash->{helper}{ID};

  Log3($name, 5, "Map_doUpdateMap($name)");

  # update location
  Map_UpdateLocation($hash);
  
  my $url = Map_CreateURL($hash);
  my $refreshInterval_ms = $hash->{helper}{RefreshInterval} * 1000;
  my $height = $hash->{helper}{FrameHeight};
  my $width = $hash->{helper}{FrameWidth};

  my $script = 
   "<script type='text/javascript'> " .
      # set new values in the variables in the DOM
      "window.parent.refreshInterval_ms_" . $id . " = $refreshInterval_ms; " .
      "window.parent.url_" . $id . " = '$url'; " .
      "window.parent.frameheight_" . $id . " = '$height'; " .
      "window.parent.framewidth_" . $id . " = '$width'; " .
    "</script>";

  $FW_RETTYPE = "text/html";
  FW_pO($script);

  return ($FW_RETTYPE, $FW_RET);
}

##################################
# Map_Store($$$$)
sub Map_Store($$$$)
{
  my ($hash, $sender, $key, $value) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{FUUID};

  my $deviceKey = $type . "_" . $name . "_" . $key;

  my $setKeyError = setKeyValue($deviceKey, $value);
  if(defined($setKeyError))
  {
    Log3($name, 3, "$sender($name) - setKeyValue $deviceKey error: $setKeyError");
  }
  else
  {
    Log3($name, 5, "$sender($name) - setKeyValue: $deviceKey -> $value");
  }
}

##################################
# Map_Restore($$$$)
sub Map_Restore($$$$)
{
  my ($hash, $sender, $key, $defaultvalue) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{FUUID};

  my $deviceKey = $type . "_" . $name . "_" . $key;

  my ($getKeyError, $value) = getKeyValue($deviceKey);
  $value = $defaultvalue
    if(defined($getKeyError) or
      not defined ($value));

  if(defined($getKeyError))
  {
    Log3($name, 3, "$sender($name) - getKeyValue $deviceKey error: $getKeyError");
  }
  else
  {
    Log3($name, 5, "$sender($name) - getKeyValue: $deviceKey -> $value");
  }

  return $value;
}

##################################
# Map_StoreRename($hash, $sender, $old_name, $key)
sub Map_StoreRename($$$$)
{
  my ($hash, $sender, $old_name, $key) = @_;
  my $type = $hash->{TYPE};
  my $new_name = $hash->{FUUID};

  my $old_deviceKey = $type . "_" . $old_name . "_" . $key;
  my $new_deviceKey = $type . "_" . $new_name . "_" . $key;

  my ($getKeyError, $value) = getKeyValue($old_deviceKey);

  if(defined($getKeyError))
  {
    Log3($new_name, 3, "$sender($new_name) - getKeyValue $old_deviceKey error: $getKeyError");
  }
  else
  {
    Log3($new_name, 5, "$sender($new_name) - getKeyValue: $old_deviceKey -> $value");

    my $setKeyError = setKeyValue($new_deviceKey, $value);
    if(defined($setKeyError))
    {
      Log3($new_name, 3, "$sender($new_name) - setKeyValue $new_deviceKey error: $setKeyError");
    }
    else
    {
      Log3($new_name, 5, "$sender($new_name) - setKeyValue: $new_deviceKey -> $value");
    }
  }

  # delete old key
  setKeyValue($old_deviceKey, undef);
}

=pod
=item device
=item summary module to display a map in fhem's UI FHEMWEB 
=begin html

  <a name="Map"></a><h3>Map</h3>
  <ul>
    This FHEM module displays a self-updating map with a certain location as center in the FHEMWEB UI.<br>
    <br>
    <a name="Map"></a><b>Define</b>
    <ul>
      <code><B>define &lt;name&gt; Map</B></code>
      <br><br>
      Example:<br>
      <ul>
        <code>
        define myMap Map<br>
        <br>
        </code>
      </ul>
    </ul><br>
    <a name="Map"></a><b>Set</b>
    <ul>
      <li><a name="Mapclearreadings">clearreadings</a><br>
        Clear all readings of the module.
      </li>
      <br>
      <li><a name="Maplongitude">longitude</a><br>
        Set longitude of the location.
      </li>
      <br>
      <li><a name="Maplatitude">latitude</a><br>
        Set latitude of the location.
      </li>
      <br>
    </ul>
    <br>
    <a name="Mapattr"></a><b>Attributes</b><br>
    <ul>
      <li><a name="MaprefreshInterval">refreshInterval</a><br>
        Interval in seconds to refresh the map.
        The default value is 5 seconds.
      </li>
      <br>
      <li><a name="Mapdisable">disable</a><br>
        If <b>0</b> (default) then Map is <b>enabled</b>.<br>
        If <b>1</b> then Map is <b>disabled</b>.<br>
      </li>
      <br>
      <li><a name="Mapdebug">debug</a><br>
        If <b>0</b> (default) debugging mode is <b>disabled</b>.<br>
        If <b>1</b> debugging mode is <b>enabled</b> - more internals and commands are shown.<br>
      </li>
      <br>
      <li><a name="MapmapProvider">mapProvider</a><br>
        Service wich generates the map.<br>
      </li>
      <br>
      <li><a name="Mapmode">mode</a><br>
        Mode of gathering the location.<br>
        <ul>
          <li><b>source</b><br>
          Latitude and Longitude are fetched from the sourcedevice.
          </li>
          <br>
          <li><b>simulation</b><br>
          Latitude and Longitude are incremented to simulate a movement.
          </li>
          <br>
          <li><b>off</b><br>
          Latitude and Longitude have to be changed by setting them.
          </li>
        </ul>
      </li>
      <br>
      <li><a name="MapsourceDeviceName">sourceDeviceName</a><br>
        Name of a FHEM device wich provides the location.<br>
      </li>
      <br>
      <li><a name="MapsourceReadingNameLatitude">sourceReadingNameLatitude</a><br>
        Name of the sourcedevice's reading wich provides the latitude of the location.<br>
      </li>
      <br>
      <li><a name="MapsourceReadingNameLongitude">sourceReadingNameLongitude</a><br>
        Name of the sourcedevice's reading wich provides the longitude of the location.<br>
      </li>
      <br>
      <li><a name="MapframeWidth">frameWidth</a><br>
        Width of the map in pixels or percent.<br>
        <br>
        Example:<br>
        <ul>
          Percentage:<br>
          <code>
          attr &lt;name&gt; frameWidth 100%<br>
          </code>
          <br>
          Pixel:<br>
          <code>
          attr &lt;name&gt; frameWidth 400<br>
          <br>
          </code>
        </ul>
      </li>
      <br>
      <li><a name="MapframeHeight">frameHeight</a><br>
        Height of the map in pixels or percent.<br>
        <br>
        Example:<br>
        <ul>
          Percentage:<br>
          <code>
          attr &lt;name&gt; frameHeight 100%<br>
          </code>
          <br>
          Pixel:<br>
          <code>
          attr &lt;name&gt; frameHeight 400<br>
          <br>
          </code>
        </ul>
      </li>
      <br>
      <li><a name="MapframeShowDetailLinkInGroup">frameShowDetailLinkInGroup</a><br>
        If enabled show Link to map's details when map is in group.<br>
        <br>
        Example:<br>
        <code>
        attr &lt;name&gt; frameShowDetailLinkInGroup 1<br>
        </code>
        <br>
      </li>
      <br>
      <li><a name="MappinIcon">pinIcon</a><br>
        Number of the icon wich marks the location.<br>
      </li>
      <br>
      <li><a name="Mapzoom">zoom</a><br>
        Zoom level 0 - 19 of the map.<br>
      </li>
    </ul><br>
    <a name="Mapreadings"></a><b>Readings</b>
    <ul>
      <li><a>Latitude</a><br>
        Latitude.<br>
      </li>
      <br>
      <li><a>Longitude</a><br>
        Longitude.<br>
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
  "abstract": "FHEM module displays a self-updating map with a certain location as center in the FHEMWEB UI",
  "x_lang": {
    "de": {
      "abstract": "FHEM-Modul zur Darstellung einer Karte"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Map"
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
