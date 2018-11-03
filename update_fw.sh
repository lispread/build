#!/bin/bash

###############################################################
# Function: wrapper script for dloader.
###############################################################

DLOADER=`pwd`/../../dloader/dloader
DEV_NAME=/dev/ttyUSB0
BAUDRATE=115200
PAC_FILE=unsc_marlin3_mcu_ZEPHYR.pac
PARAMS="-dev ${DEV_NAME} -baud ${BAUDRATE} -pac ${PAC_FILE}"
IMGS_DIR=`pwd`
BOOT_IMG=mcuboot-pubkey.bin
KERNEL_IMG=zephyr-signed-ota.bin
MODEM_IMG=
USERDATA_IMG=

usage()
{
	echo "Usage: `basename $0` [-d] path [-abhkmu]"
	echo "−d: specify the path which contains images."
	echo "−a: flash all images."
	echo "−b: flash bootloader."
	echo "−k: flash kernel."
	echo "−m: flash modem."
	echo "−u: flash userdata"
	echo "−h: display help."
	echo ""
	exit 0
}

append_params()
{
	if [ -d ${IMGS_DIR} ]; then
		for PAR in $@; do
			IMG_NAME=`eval echo '$'"${PAR}"_IMG""`
			IMG_PATH=`find ${IMGS_DIR} -type f -iname $(eval echo ${IMG_NAME})`
			[ -n "${IMG_PATH}" ] && PARAMS="${PARAMS} -${PAR} ${IMG_PATH}"
		done
	fi
}

NO_ARGS=0
if [ $# -eq $NO_ARGS ]; then
	append_params BOOT KERNEL MODEM USERDATA
fi

while getopts ":abkmuhd:" opt; do
	case $opt in
	d ) IMGS_DIR=$OPTARG;;
	a ) append_params BOOT KERNEL MODEM USERDATA;;
	b ) append_params BOOT;;
	k ) append_params KERNEL;;
	m ) append_params MODEM;;
	u ) append_params USERDATA;;
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

sudo ${DLOADER} ${PARAMS}
