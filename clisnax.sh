#!/bin/bash

DOPRINT=""
CLEOS="/usr/local/bin/clisnax"
ALIST=( \
    "http://127.0.0.1:8888" \
    "https://cdn.snax.one:443" \
    "http://p1-snax.eosph.io:8859" \
    "http://speer1.nodeone.io:8876" \
    "http://sxn1.eosviet.io:8858" \
    "http://snax-peer1.eoskh.com:8877" \
    )
KLIST=( \
    "http://127.0.0.1:8900" \
    )
IGNORE=( \
    )

if [ ! -x $CLEOS ] ; then
    echo "Cannot run program $CLEOS"
    exit 1
fi
if [ -x /usr/local/bin/curl ] ; then
    CURL=/usr/local/bin/curl
elif [ -x /usr/bin/curl ] ; then
    CURL=/usr/bin/curl
else
    echo "Cannot find curl program"
    exit 1
fi
for api in ${ALIST[@]} ; do
    if [ $DOPRINT ] ; then  echo "Checking API node $api"; fi
    CHECKHOST=$(echo $api|sed -e"s/^.*:\/\///")
    /bin/nc -zvw 1 ${CHECKHOST//:/ } >&/dev/null
    if [[ $? -eq 0 ]] ; then
        HEADTIME=$($CURL --connect-timeout 10 --max-time 15 -s $api/v1/chain/get_info | jq -r '.head_block_time')
        if [[ "$HEADTIME" = "" ]] ; then
            if [ $DOPRINT ] ; then  echo "NFG: no headtime"; fi
            continue
        fi
        HEADSEC=$(date -u -d $HEADTIME +"%s")
        NOW=$(date -u +"%s")
        DIFF="$(($NOW-$HEADSEC))"
        if [ $DIFF -gt 0 ] ; then
            if [ $DOPRINT ] ; then  echo "$api: headtime difference ($DIFF)"; fi
            continue
        else
            if [ $DOPRINT ] ; then  echo "Setting --url $api"; fi
            URL="--url $api"
            break
        fi
    else
        if [ $DOPRINT ] ; then  echo "$api: NFG no connection"; fi
        continue
    fi
done

KXDPROC=$(ps aux | grep kxd | grep -Ev "grep|defunct|wallet-dir=")
if [[ "$KXDPROC" != "" ]] ; then
    PROCNUM=$(echo $KXDPROC | awk '{print $2}')
    SOCKPIPE=$(lsof -p $PROCNUM | grep kxd.sock | grep STREAM)
    if [[ $PROCNUM -gt 100 ]] ; then
        KXD=""
    else
        die "Bogus kxd process found\n$KXDPROC"
    fi
else
    # We did not find local kxd pipe, let's check for network connection to a wallet server.
    for key in ${KLIST[@]} ; do
        CHECKHOST=$(echo $key|sed -e"s/^.*:\/\///")
        #echo -n "Testing ($key) checkhost ($CHECKHOST) nc arg (${CHECKHOST//:/ })..."
        /bin/nc -zvw 2 ${CHECKHOST//:/ } >&/dev/null
        if [[ $? -eq 0 ]] ; then
            KXD="--wallet-url $key"
            break
        fi
    done
    if [[ "$KXD" = "" ]] ; then
        echo "No wallet server found"
    fi
fi

$CLEOS $URL $KXD "$@"
exit $?
