#!/bin/bash

# dovote.sh -jem
# Find and vote for top 30 registered BPs.

# Set defaults
PROD="myproducername"
WALLET_NAME="myprodvote"
WALLET_FILE="$HOME/snax/wallets/wallet.myprod.vote"
THIS_KEY="vote"

usage() {
    echo "Usage: $0 -p prod -w wallet -s wallet_pw_file -k keyname -R [run for real, otherwise pront actions]"
    echo "Example: $0 -p myproducername -w vote -s pw_vote -k vote"
    echo ""
}

checkopts() {
    if [ -x  /usr/local/bin/clisnax.sh ] ; then
        CLEOS="/usr/local/bin/clisnax.sh"
    elif [ -x  /usr/local/bin/clisnax ] ; then
        # Switch the order of these, if local API exists and is reliable.
        APINODE="--url https://cdn.snax.one"
        APINODE="--url http://127.0.0.1:8888"
        WURL="--wallet-url http://127.0.0.1:8900"
        WURL=""
        CLEOS="/usr/local/bin/clisnax $APINODE $WURL"
        # This should start kxd, if avilable locally
        /usr/local/bin/clisnax wallet list >/dev/null 2>&1
    else
        die "No clisnax executable found"
    fi
    while getopts ":Rk:w:s:p:" opt; do
        case "$opt" in
            p)  PROD="$OPTARG" ;;
            w)  WALLET_NAME="$OPTARG" ;;
            s)  WALLET_FILE="$OPTARG" ;;
            k)  THIS_KEY="$OPTARG" ;;
            R)  FORREAL="1" ;;
            *)  usage && echo "Unrecognized option $OPTARG" && die ;;
        esac
    done
}

main()
{
    checkopts $@
    checklock
    make_vote_list
    do_vote
    $CLEOS wallet lock_all > /dev/null
    exit 0
}

do_vote() {
    unlock_wallet $WALLET_NAME $WALLET_FILE
    echo $CLEOS system voteproducer prods $PROD $VLIST -p $PROD@$THIS_KEY
    [ $FORREAL ] && $CLEOS system voteproducer prods $PROD $VLIST -p $PROD@$THIS_KEY
}

make_vote_list() {
    # Initialize
    VLIST='' && counter=0
    # Active only, unreged producer will cause vote fail.
    make_active_producer_list
    make_ignore_list
    if [[ "$CHAINPRODLIST" = "" ]] ; then
        die "Function ${FUNCNAME[0]}: Failed to get producer list for voting"
    fi
    # We run through the list of BPs and filter out those we do not want.
    for CheckProd in ${CHAINPRODLIST[@]} ; do
        # IgnoreBP list
        [[ ${IGNOREBP[$CheckProd]} ]] && continue
        # Adding producer $CheckProd
        VLIST="$VLIST $CheckProd"
        # EOSIO allows up to 30 votes
        let $((counter++))
        [[ $counter -ge 30 ]] && break
    done
    [[ "$VLIST" = "" ]] && die "Function ${FUNCNAME[0]}: Failed to get any producer to vote for"
}


make_ignore_list() {
    declare -Ag IGNOREBP
    IGNORELIST="\
        snaxprod1 \
        snaxprod2 \
        snaxprod3 \
        snaxprod4 \
        extranode1 \
        extranode2 \
    "
    for ignorebp in ${IGNORELIST[@]} ; do
        IGNOREBP[$ignorebp]=true
    done
}

make_active_producer_list() {
    # Exercise clisnax
    $CLEOS wallet list &>/dev/null
    # Get up to 100 top producers, removing unreged producers
    CHAINPRODLIST=$($CLEOS system listproducers -l 101 | grep -E "^[a-z1-5]" | grep -v 111111111111 | sort | awk '{print $1}')
    if [[ "$CHAINPRODLIST" = "" ]] ; then
        die "Function ${FUNCNAME[0]}: Failed to get producer list"
    fi
}


unlock_wallet() {
    local unlock_wallet=$1
    local unlock_file=$2
    check_open_wallet $unlock_wallet
    if [ ! -r $unlock_file ] ; then
        die "Function ${FUNCNAME[0]}: Cannot read wallet pw file $unlock_file"
    fi
    if [ ! $OPENWALLET ] ; then
        $CLEOS wallet unlock -n $unlock_wallet --password $(cat $unlock_file) > /dev/null
    else
        return
    fi
    # Now, make sure it is open, or die
    check_open_wallet $unlock_wallet
    if [ ! $OPENWALLET ] ; then
        die "Function ${FUNCNAME[0]}: Failed to unlock wallet $unlock_wallet"
    fi
}

check_open_wallet() {
    local check_wallet=$1
    OPENWALLET=''
    # Not sure why, but this lubricates things. Maybe DNS lookups?
    $CLEOS wallet list &>/dev/null
    local wallet_open=$($CLEOS wallet list | grep $check_wallet)
    [[ $wallet_open =~ \* ]] && OPENWALLET=1
    # return OPENWALLET
}

die() { echo "$@" 1>&2 ; exit 1; }

PROGNAME=${0##*/}
LOCKFILE="/var/lock/$PROGNAME"
LOCKFD=98

# PRIVATE
_lock()             { flock -$1 $LOCKFD; }
_no_more_locking()  { _lock u; _lock xn && rm -f $LOCKFILE; }
_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\""; trap _no_more_locking EXIT; }
# PUBLIC
exlock_now()        { _lock xn; }  # obtain an exclusive lock immediately or fail
exlock()            { _lock x; }   # obtain an exclusive lock
shlock()            { _lock s; }   # obtain a shared lock
unlock()            { _lock u; }   # drop a lock
checklock() {
    _prepare_locking # ON START
    exlock_now || die "$PROGNAME already running" # Simplest example is avoiding running multiple instances of script.
}



main $@
exit 0

