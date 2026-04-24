#!/bin/sh
#
# FreeSWITCH Modular Media Switching Software Library / Soft-Switch Application
# Copyright (C) 2005-2016, Anthony Minessale II <anthm@freeswitch.org>
#
# Version: MPL 1.1
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
# http://www.mozilla.org/MPL/F
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.
#
# The Original Code is FreeSWITCH Modular Media Switching Software Library / Soft-Switch Application
#
# The Initial Developer of the Original Code is
# Michael Jerris <mike@jerris.com>
# Portions created by the Initial Developer are Copyright (C)
# the Initial Developer. All Rights Reserved.
#
# Contributor(s):
#
#  Sergey Safarov <s.safarov@gmail.com>
#

BASEURL=http://files.freeswitch.org
PID_FILE=/var/run/freeswitch/freeswitch.pid


get_password() {
    < /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-12};echo;
}

get_sound_version() {
    local SOUND_TYPE=$1
    grep "$SOUND_TYPE" /scripts/sounds_version.txt | sed -E "s/$SOUND_TYPE\s+//"
}

wget_helper() {
    local SOUND_FILE=$1
    grep -q $SOUND_FILE /usr/local/freeswitch/sounds/soundfiles_present.txt 2> /dev/null
    if [ "$?" -eq 0 ]; then
        echo "Skipping download of $SOUND_FILE. Already present"
        return
    fi
    wget $BASEURL/$SOUND_FILE
    if [ -f $SOUND_FILE ]; then
        echo $SOUND_FILE >> /usr/local/freeswitch/sounds/soundfiles_present.txt
    fi
}

download_sound_rates() {
    local i
    local f
    local SOUND_TYPE=$1
    local SOUND_VERSION=$2

    for i in $SOUND_RATES
    do
        f=freeswitch-sounds-$SOUND_TYPE-$i-$SOUND_VERSION.tar.gz
        echo "Downloading $f"
        wget_helper $f
    done
}

download_sound_types() {
    local i
    local SOUND_VERSION
    for i in $SOUND_TYPES
    do
        SOUND_VERSION=$(get_sound_version $i)
        download_sound_rates $i $SOUND_VERSION
    done
}

extract_sound_files() {
    local SOUND_FILES=freeswitch-sounds-*.tar.gz
    for f in $SOUND_FILES
    do
        if [ -f $f ]; then
            echo "Extracting file $f"
            tar xzf $f -C /usr/local/freeswitch/sounds/
        fi
    done
}

delete_archives() {
    local FILES_COUNT=$(ls -1 freeswitch-sounds-*.tar.gz 2> /dev/null | wc -l)
    if [ "$FILES_COUNT" -ne 0 ]; then
        echo "Removing downloaded 'tar.gz' archives"
        rm -f freeswitch-sounds-*.tar.gz
    fi
}

SOUND_RATES=$(echo "$SOUND_RATES" | sed -e 's/:/\n/g')
SOUND_TYPES=$(echo "$SOUND_TYPES" | sed -e 's/:/\n/g')

if [ -z "$SOUND_RATES" -o -z "$SOUND_TYPES" ]; then
	echo "Environment variables 'SOUND_RATES' or 'SOUND_TYPES' not defined. Skipping sound files checking."
else
	download_sound_types
	extract_sound_files
	delete_archives
fi

if [ "$EPMD"="true" ]; then
    /usr/bin/epmd -daemon
fi

echo "Setting INTERNAL_API_BASE_URL to ${INTERNAL_API_BASE_URL}"
sed -i "s|internal_api_base_url=.*\"|internal_api_base_url=${INTERNAL_API_BASE_URL}\"|" /usr/local/freeswitch/conf/vars.xml
sed -i "s|internal_api_username=.*\"|internal_api_username=${INTERNAL_API_USERNAME}\"|" /usr/local/freeswitch/conf/vars.xml
sed -i "s|internal_api_password=.*\"|internal_api_password=${INTERNAL_API_PASSWORD}\"|" /usr/local/freeswitch/conf/vars.xml


# SIP_BIND_IP - The PRIVATE IP that FreeSWITCH binds to and advertises in heartbeat
# In DigitalOcean, set this to your droplet's private IP so Kamailio can discover FreeSWITCH
# In AWS, local_ip_v4 auto-detects correctly so this is optional
if [ -n "$SIP_BIND_IP" ]; then
    echo "Setting SIP_BIND_IP (private IP for heartbeat) to ${SIP_BIND_IP}"
    sed -i "s|sip_bind_ip=.*\"|sip_bind_ip=${SIP_BIND_IP}\"|" /usr/local/freeswitch/conf/vars.xml
fi


DEFAULT_EXTERNAL_SIP_IP="stun:stun.freeswitch.org"
# Check if external_sip_ip environment variable is set, and assign the appropriate value
if [ -n "$EXTERNAL_SIP_IP" ]; then
    EXTERNAL_SIP_IP_VALUE=$EXTERNAL_SIP_IP
else
    EXTERNAL_SIP_IP_VALUE=$DEFAULT_EXTERNAL_SIP_IP
fi
sed -i "s|external_sip_ip=.*\"|external_sip_ip=${EXTERNAL_SIP_IP_VALUE}\"|" /usr/local/freeswitch/conf/vars.xml


DEFAULT_EXTERNAL_RTP_IP="stun:stun.freeswitch.org"
# Check if external_rtp_ip environment variable is set, and assign the appropriate value
if [ -n "$EXTERNAL_RTP_IP" ]; then
    EXTERNAL_RTP_IP_VALUE=$EXTERNAL_RTP_IP
else
    EXTERNAL_RTP_IP_VALUE=$DEFAULT_EXTERNAL_RTP_IP
fi
sed -i "s|external_rtp_ip=.*\"|external_rtp_ip=${EXTERNAL_RTP_IP_VALUE}\"|" /usr/local/freeswitch/conf/vars.xml



DEFAULT_RTP_START_PORT="16384"
DEFAULT_RTP_END_PORT="32768"
# Check if rtp_start_port environment variable is set, and assign the appropriate value
if [ -n "$RTP_START_PORT" ]; then
    RTP_START_PORT_VALUE=$RTP_START_PORT
else
    RTP_START_PORT_VALUE=$DEFAULT_RTP_START_PORT
fi

# Check if rtp_end_port environment variable is set, and assign the appropriate value
if [ -n "$RTP_END_PORT" ]; then
    RTP_END_PORT_VALUE=$RTP_END_PORT
else
    RTP_END_PORT_VALUE=$DEFAULT_RTP_END_PORT
fi

sed -i "s|rtp_start_port=.*\"|rtp_start_port=${RTP_START_PORT_VALUE}\"|" /usr/local/freeswitch/conf/vars.xml
sed -i "s|rtp_end_port=.*\"|rtp_end_port=${RTP_END_PORT_VALUE}\"|" /usr/local/freeswitch/conf/vars.xml




# if [ ! -f "/etc/freeswitch/freeswitch.xml" ]; then
#     SIP_PASSWORD=$(get_password)
#     mkdir -p /etc/freeswitch
#     cp -varf /usr/share/freeswitch/conf/vanilla/* /etc/freeswitch/
#     sed -i -e "s/default_password=.*\?/default_password=$SIP_PASSWORD\"/" /etc/freeswitch/vars.xml
#     echo "New FreeSwitch password for SIP calls set to '$SIP_PASSWORD'"
# fi

trap '/usr/src/freeswitch/freeswitch -stop' SIGTERM

/usr/src/freeswitch/freeswitch -nc -nf -nonat &
pid="$!"

wait $pid
exit 0
