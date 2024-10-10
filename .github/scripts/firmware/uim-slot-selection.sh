#!/bin/bash

# This script automatically configures the UIM application for Qualcomm QMI modems with more than one sim slot.

# Define the wait time for SIM detection.
sim_wait_time=4

# Check the system type and skip configuration if not applicable.
case "$(cat /sys/devices/soc0/machine)" in
    APQ*)
        echo "Skipping SIM configuration on APQ SoC."
        exit 0
esac

# Check if qmicli is installed.
if ! [ -x "$(command -v qmicli)" ]; then
    echo "Error: qmicli is not installed."
    exit 1
fi

# Prepare a qmicli command with the desired modem path.
count=0
QMICLI_MODEM=""

# Wait for the modem to appear.
while [ -z "$QMICLI_MODEM" ] && [ "$count" -lt "45" ]; do
    if [ -e "/dev/modem" ]; then
        QMICLI_MODEM="qmicli --silent -d /dev/modem"
        echo "Using /dev/modem"
    elif [ -e "/dev/wwan0qmi0" ]; then
        QMICLI_MODEM="qmicli --silent -d /dev/wwan0qmi0 --device-open-qmi"
        echo "Using /dev/wwan0qmi0"
    elif qmicli --silent -pd qrtr://0 --uim-noop > /dev/null; then
        QMICLI_MODEM="qmicli --silent -pd qrtr://0"
        echo "Using qrtr://0"
    fi
    sleep 1
    count=$((count+1))
done
echo "Waited $count seconds for modem device to appear."

# Check if modem is available.
if [ -z "$QMICLI_MODEM" ]; then
    echo "Error: No modem available."
    exit 2
fi

# Get the card status.
QMI_CARDS=$($QMICLI_MODEM --uim-get-card-status)

# Wait until a SIM card is detected.
count=0
while ! printf "%s" "$QMI_CARDS" | grep -Fq "Card state: 'present'"; do
    if [ "$count" -ge "$sim_wait_time" ]; then
        echo "Error: No SIM detected after $sim_wait_time seconds."
        exit 4
    fi
    sleep 1
    count=$((count+1))
    QMI_CARDS=$($QMICLI_MODEM --uim-get-card-status)
done
echo "Waited $count seconds for modem to come up."

# Clear the selected application in case the modem is in a bugged state.
if ! printf "%s" "$QMI_CARDS" | grep -Fq "Primary GW:   session doesn't exist"; then
    echo 'Warning: Application was already selected.'
    $QMICLI_MODEM --uim-change-provisioning-session='activate=no,session-type=primary-gw-provisioning' > /dev/null
fi

# Extract the first available slot number and AID for the USIM application.
FIRST_PRESENT_SLOT=$(printf "%s" "$QMI_CARDS" | grep "Card state: 'present'" -m1 -B1 | head -n1 | cut -c7-7)
FIRST_PRESENT_AID=$(printf "%s" "$QMI_CARDS" | grep "usim (2)" -m1 -A3 | tail -n1 | awk '{print $1}')

echo "Selecting $FIRST_PRESENT_AID on slot $FIRST_PRESENT_SLOT."

# Send the new configuration to the modem.
$QMICLI_MODEM --uim-change-provisioning-session="slot=$FIRST_PRESENT_SLOT,activate=yes,session-type=primary-gw-provisioning,aid=$FIRST_PRESENT_AID" > /dev/null
exit $?

