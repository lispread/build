#!/bin/bash

###############################################################
# Function: wrapper script for dloader.
###############################################################

DLOADER=dloader
DEV_NAME=ttyUSB0
BAUDRATE=115200
IMGS_DIR=`pwd`
FDL_IMG=fdl*
BOOT_IMG=mcuboot-pubkey*
KERNEL_IMG=zephyr-signed-ota*
MODEM_IMG=wcn-modem*
USERDATA_IMG=

usage()
{
	echo "Usage: `basename $0` [-d] device [-i] path [-abhkmu]"
	echo "-d: specify the device name of the serial port."
	echo "-i: specify the path which contains images."
	echo "-a: flash all images."
	echo "-b: flash bootloader."
	echo "-k: flash kernel."
	echo "-m: flash modem."
	echo "-u: flash userdata"
	echo "-h: display help."
	echo ""
	exit 0
}

append_params()
{
	if [ -d ${IMGS_DIR} ]; then
		for PAR in $@; do
			IMG_NAME=`eval echo '$'"${PAR}"_IMG""`
			IMG_PATH=`find ${IMGS_DIR} -type f -iname $(eval echo ${IMG_NAME})`
			[ -n "${IMG_PATH}" ] && EXTRA_PARAMS="${EXTRA_PARAMS} -${PAR} ${IMG_PATH}"
		done
	fi
}

NO_ARGS=0
if [ $# -eq $NO_ARGS ]; then
	append_params FDL BOOT KERNEL MODEM USERDATA
fi

while getopts ":abkmuhd:i:" opt; do
	case $opt in
	d ) DEV_NAME=$OPTARG;;
	i ) IMGS_DIR=$OPTARG;;
	a ) append_params FDL BOOT KERNEL MODEM USERDATA;;
	b ) append_params FDL BOOT;;
	k ) append_params FDL KERNEL;;
	m ) append_params FDL MODEM;;
	u ) append_params FDL USERDATA;;
	h ) usage;return;;
	* ) echo "Unimplemented option chosen.";; # DEFAULT
	esac
done
shift $(($OPTIND - 1))

if [ -d ${IMGS_DIR} ]; then
	pushd ${IMGS_DIR}
	echo
else
	echo "No such directory: ${IMGS_DIR}"
	exit
fi

PARAMS="-dev /dev/${DEV_NAME} -baud ${BAUDRATE} ${EXTRA_PARAMS}"
sudo ${DLOADER} ${PARAMS}
