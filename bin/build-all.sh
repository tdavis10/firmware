#!/bin/bash

set -e

VERSION=`bin/buildinfo.py`

COUNTRIES="US EU433 EU865 CN JP ANZ KR"
#COUNTRIES=US
#COUNTRIES=CN

BOARDS_ESP32="tlora-v2 tlora-v1 tlora-v2-1-1.6 tbeam heltec tbeam0.7"
#BOARDS_ESP32=tbeam

# FIXME note nrf52840dk build is for some reason only generating a BIN file but not a HEX file nrf52840dk-geeksville is fine
BOARDS_NRF52="lora-relay-v1"

NUM_JOBS=2

OUTDIR=release/latest

# We keep all old builds (and their map files in the archive dir)
ARCHIVEDIR=release/archive 

rm -f $OUTDIR/firmware*

mkdir -p $OUTDIR/bins
rm -r $OUTDIR/bins/*
mkdir -p $OUTDIR/bins/universal $OUTDIR/elfs/universal

# build the named environment and copy the bins to the release directory
function do_build() {
	BOARD=$1
	COUNTRY=$2
	isNrf=$3
	
    echo "Building $COUNTRY for $BOARD with $PLATFORMIO_BUILD_FLAGS"
    rm -f .pio/build/$BOARD/firmware.*

    # The shell vars the build tool expects to find
    export APP_VERSION=$VERSION

    # Are we building a universal/regionless rom?
    if [ "x$COUNTRY" != "x" ]
    then
        export HW_VERSION="1.0-$COUNTRY"
        export COUNTRY
        basename=firmware-$BOARD-$COUNTRY-$VERSION
    else
        export HW_VERSION="1.0"
        unset COUNTRY
        basename=universal/firmware-$BOARD-$VERSION
    fi

    pio run --jobs $NUM_JOBS --environment $BOARD # -v
    SRCELF=.pio/build/$BOARD/firmware.elf
    cp $SRCELF $OUTDIR/elfs/$basename.elf

    if [ "$isNrf" = "false" ]
    then
        echo "Copying ESP32 bin file"
        SRCBIN=.pio/build/$BOARD/firmware.bin
        cp $SRCBIN $OUTDIR/bins/$basename.bin
    else
        echo "Generating NRF52 uf2 file"
        SRCHEX=.pio/build/$BOARD/firmware.hex
        bin/uf2conv.py $SRCHEX -c -o $OUTDIR/bins/$basename.uf2 -f 0xADA52840
    fi
}

function do_boards() {
	declare boards=$1
	declare isNrf=$2
	for board in $boards; do
		for country in $COUNTRIES; do 
		    do_build $board $country "$isNrf"   
		done

		# Build universal
		do_build $board "" "$isNrf" 
	done
}

# Make sure our submodules are current
git submodule update 

# Important to pull latest version of libs into all device flavors, otherwise some devices might be stale
platformio lib update 

do_boards "$BOARDS_ESP32" "false"
do_boards "$BOARDS_NRF52" "true"

echo "Building SPIFFS for ESP32 targets"
pio run --environment tbeam -t buildfs
cp .pio/build/tbeam/spiffs.bin $OUTDIR/bins/universal/spiffs-$VERSION.bin

# keep the bins in archive also
cp $OUTDIR/bins/firmware* $OUTDIR/bins/universal/spiffs* $OUTDIR/elfs/firmware* $OUTDIR/bins/universal/firmware* $OUTDIR/elfs/universal/firmware* $ARCHIVEDIR

echo Updating android bins $OUTDIR/forandroid
rm -rf $OUTDIR/forandroid
mkdir -p $OUTDIR/forandroid
cp -a $OUTDIR/bins/universal/*.bin $OUTDIR/forandroid/

cat >$OUTDIR/curfirmwareversion.xml <<XML
<?xml version="1.0" encoding="utf-8"?>

<!-- This file is kept in source control because it reflects the last stable
release.  It is used by the android app for forcing software updates.  Do not edit.
Generated by bin/buildall.sh -->

<resources>
    <string name="cur_firmware_version">$VERSION</string>
</resources>
XML

echo Generating $ARCHIVEDIR/firmware-$VERSION.zip
rm -f $ARCHIVEDIR/firmware-$VERSION.zip
zip --junk-paths $ARCHIVEDIR/firmware-$VERSION.zip $ARCHIVEDIR/spiffs-$VERSION.bin $OUTDIR/bins/firmware-*-$VERSION.* images/system-info.bin bin/device-install.sh bin/device-update.sh

echo BUILT ALL
