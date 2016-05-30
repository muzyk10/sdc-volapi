#!/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2016, Joyent, Inc.
#

if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: '\
        '${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail

TOP=$(cd $(dirname $0)/../../; pwd)

ssh root@coal /bin/bash -l << "EOS"
if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: '\
        '${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

set -o errexit
set -o pipefail

function fatal
{
    echo "$0: fatal error: $*"
    exit 1
}

function errexit
{
    [[ $1 -ne 0 ]] || exit 0
    fatal "error exit status $1"
}

trap 'errexit $?' EXIT

# Install platform with dockerinit changes allowing to automatically mount
# NFS server zones' exported filesystems from Docker containers.
sdcadm platform install -C experimental \
    $(updates-imgadm list -H -o uuid -C experimental name=platform \
        version=~nfsvolumes | tail -1)

# Assign that platform to all CNs
sdcadm platform assign --all \
    $(updates-imgadm list -H -o version -C experimental name=platform \
        version=~nfsvolumes | tail -1 | cut -d'-' -f2)

sdcadm_experimental_images=$(/opt/smartdc/bin/updates-imgadm -H \
    -C experimental \
    list name=sdcadm | cut -d ' ' -f 1)

# Find latest sdcadm image with tritonnfs support
latest_sdcadm_tritonnfs_img=
for SDC_ADM_IMG in ${sdcadm_experimental_images};\
do
    latest_sdcadm_tritonnfs_img=$(updates-imgadm -C experimental get \
        "${SDC_ADM_IMG}" | \
        json -c 'tags.buildstamp.indexOf("nfs") !== -1' uuid)
done

if [ "x$latest_sdcadm_tritonnfs_img" != "x" ]; then
    echo "Updating sdcadm to image ${latest_sdcadm_tritonnfs_img}"
    sdcadm self-update -C experimental $latest_sdcadm_tritonnfs_img
else
    fatal "Could not find latest sdcadm version with tritonnfs support"
fi

echo "Enabling experimental VOLAPI service"
sdcadm experimental volapi

EOS

echo "VOLAPI setup, reboot of all CNs is needed before it can be used"