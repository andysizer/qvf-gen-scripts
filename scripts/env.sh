#!/bin/bash

export MAGIC='--testnet-magic 1097911063'

# === CHANGE THESE VARIABLES ACCORDINGLY === #
export CARDANO_NODE_SOCKET_PATH="$HOME/node.socket"
export preDir="$HOME/code/snapbrillia/quadraticvoting/testnet"
export cli="cardano-cli"
export qvf="qvf-cli"
# export qvf="cabal run qvf-cli --"
# ========================================== #

export keyHolder="keyHolder"
export keyHoldersAddress=$(cat "$preDir/$keyHolder.addr")
export keyHoldersPubKeyHash=$(cat "$preDir/$keyHolder.pkh")
export keyHoldersSigningKeyFile="$preDir/$keyHolder.skey"
export scriptLabel="qvf"
export scriptPlutusFile="$preDir/$scriptLabel.plutus"
export scriptAddressFile="$preDir/$scriptLabel.addr"
export policyIdFile="$preDir/$scriptLabel.symbol"
export policyId=$(cat $policyIdFile)
export tokenNameHexFile="$preDir/token.hex"
export policyScriptFile="$preDir/minting.plutus"
export authAssetUTxOFile="$preDir/authAsset.utxo"
export protocolsFile="$preDir/protocol.json"
export txBody="$preDir/tx.unsigned"
export txSigned="$preDir/tx.signed"

# Removes the double quotes.
#
# Takes 1 argument:
#   1. Target string.
remove_quotes() {
  echo $1           \
  | sed 's|[",]||g'
}


# Generates a key pair.
#
# Takes 1 argument:
#   1. Label for files.
generate_skey_and_vkey() {
    $cli address key-gen                        \
        --verification-key-file $preDir/$1.vkey \
        --signing-key-file $preDir/$1.skey
}


# Creates an address file from a verification file.
# 
# Takes 1 argument:
#   1. Label for files.
vkey_to_address() {
    $cli address build                                  \
        $MAGIC                                          \
        --payment-verification-key-file $preDir/$1.vkey \
        --out-file $preDir/$1.addr
}


# Creates a public key hash file from a verification file.
# 
# Takes 1 argument:
#   1. Label for files.
vkey_to_public_key_hash() {
    $cli address key-hash                               \
        --payment-verification-key-file $preDir/$1.vkey \
        --out-file $preDir/$1.pkh
}


# Creates the associated address from a Plutus script File.
# 
# Doesn't take any arguments, uses global variables.
plutus_script_to_address() {
    $cli address build-script           \
        $MAGIC                          \
        --script-file $scriptPlutusFile \
        --out-file $scriptAddressFile
}


# Given a numeric range (inclusive), generates all four files of a wallet
# (.vkey, .skey, .addr, .pkh) for each number.
#
# This function has builtin safety to prevent rewrites and wallet loss.
#
# For now, the maximum number of generated wallets is capped at 100.
# 
# Takes 2 arguments:
#   1. Starting number,
#   2. Ending number.
generate_wallets_from_to() {

    max_amt=100

    if [ `expr $2 - $1` -ge $max_amt ]
    then
    echo "That's over 100 wallets generated. Please reconsider. Edit fn if you really want to."
    else

    # Important part
    for i in $(seq $1 $2)
    do
    if [ -f $preDir/$i.vkey ] || [ -f $preDir/$i.skey ] || [ -f $preDir/$i.addr ] || [ -f $preDir/$i.pkh ]
    then

    echo "Error! $i.vkey, $i.skey, $i.addr, or $i.pkh already exist. Move/rename/remove them first and run again."
    break

    else

    generate_skey_and_vkey $i
    vkey_to_address $i
    vkey_to_public_key_hash $i

    fi
    done
    fi
}


# Returns the "first" UTxO from a wallet (the first in the table returned by
# the `cardano-cli` application), formatted as `<txId>#<txIndex>`.
#
# Takes 1 argument:
#   1. Wallet number/name.
get_first_utxo_of() {
    echo `$cli query utxo                 \
        --address $(cat $preDir/$1.addr)  \
        $MAGIC                            \
        | sed 1,2d                        \
        | awk 'FNR == 1 {print $1"#"$2}'`
}
get_nth_utxo_of() {
    echo `$cli query utxo                    \
        --address $(cat $preDir/$1.addr)     \
        $MAGIC                               \
        | sed 1,2d                           \
        | awk 'FNR == '$2' {print $1"#"$2}'`
}


# Returns a list of all UTxO's available at the given wallet address file, each
# prefixed with "--tx-in" for convenient use while constructing a transaction.
# 
# Takes 1 argument:
#   1. Wallet number/name.
get_all_input_utxos_at() {
    echo `$cli query utxo                             \
        --address $(cat $preDir/$1.addr)              \
        $MAGIC                                        \
        | sed 1,2d                                    \
        | awk '{print $1"#"$2}'                       \
        | sed 's/^/--tx-in /'                         \
        | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/ /g'`
}


# Displays the utxo information table of one or multiple addresses.
#
# Takes at least 1 argument:
#   1. Wallet number/name,
#   *. Any additional wallet number/name.
show_utxo_tables () {
    for i in $@
    do
        echo
        echo $i
        cardano-cli query utxo               \
            --address $(cat $preDir/$i.addr) \
            $MAGIC
    done
}

# Given a numeric range (inclusive), displays the utxo information table from
# the address of the .addr file of each number, and displays any addresses
# provided after the numeric range.
# Takes at least 2 arguments:
#
#   1. Starting number,
#   2. Ending number,
#   *. Any additional wallet address files.
show_utxo_tables_from_to () {

    for i in $(seq $1 $2)
    do
        echo "$preDir/$i.addr utxos: "
        show_utxo_tables $i
    done

    shift 2
    if [ -n $1 ]
    then
        echo "$preDir/$i.addr utxos: "
        show_utxo_tables $@
    fi
}

# Equally distributes a given total Lovelace count from a wallet, between a
# number of wallets designated with a numeric range.
#
# Consumes all the available UTxO's, and returns the change back to the same
# wallet.
#
# TODO: Might require fixing as it can't handle UTxO's carrying tokens. It's
#       not a harmful limitation, it just fails if the given wallet has tokens
#       stored inside.
#
# Takes 4 arguments:
#   1. The spending wallet number/name,
#   2. Starting number of the receiving wallets,
#   3. Ending number of the receiving wallets,
#   4. Total amount of Lovelace to be distributed equally,
distribute_from_to_wallets() {

    spendingAddr=$(cat $preDir/$1.addr)
    tx_in_str=$(get_all_input_utxos_at $1)
    tx_out_str=''
    num_of_wallets=`expr $3 - $2`
    num_of_wallets=`expr $num_of_wallets + 1` # +1 to compensate range inclusivity.
    lovelace_amt=`expr $4 / $num_of_wallets`

    # Potential change: we could query the total amount of lovelace at all
    # UTxO's of spending wallet instead of relying on Arg4; but the current
    # way provides flexibility of limiting the amount to spend

    # Build the string of --tx-out's
    for i in $(seq $2 $3)
    do
        addr=$(cat $preDir/$i.addr)
        tx_out_str=$tx_out_str' --tx-out '$addr'+'$lovelace_amt
        # tx_out_str="$tx_out_str --tx-out \"$addr + $lovelace_amt\""
    done
  
    # Helper logs:
    echo "Starting to distribute a total of $4 Lovelaces between $num_of_wallets number of wallets."
    echo "(Each wallet will receive $lovelace_amt Lovelaces)."
    echo
    echo "Input UTxO's are:"
    echo $tx_in_str
    echo
    echo "Output addresses are:"
    echo $tx_out_str

    # Transaction
    $cli transaction build             \
        --babbage-era                  \
        $MAGIC                         \
        $tx_in_str                     \
        --change-address $spendingAddr \
        $tx_out_str                    \
        --out-file $txBody

    $cli transaction sign                  \
        --tx-body-file $txBody             \
        --signing-key-file $preDir/$1.skey \
        $MAGIC                             \
        --out-file $txSigned

    $cli transaction submit \
        $MAGIC              \
        --tx-file $txSigned
}


# Drains a range of wallets into a single wallet. The receiving wallet will
# end up with 2 UTxO's: One holding 1 ADA, while the other holds the rest of
# the spent Lovelaces.
#
# TODO: Might require fixing as it can't handle UTxO's carrying tokens. It's
#       not a harmful limitation, it just fails if the given wallet has tokens
#       stored inside.
#
# Takes 3 arguments:
#   1. Starting number of the spending wallets,
#   2. Ending number of the spending wallets,
#   3. Receiving wallet's number/name.
drain_from_wallets_to() {

    tx_in_str=''
    signing_keys_str=''

    # Build the string of --tx-in's
    for i in $(seq $1 $2)
    do
        # tx_in_str=$tx_in_str$(get_all_input_utxos_at $i)' '
        tx_in_str="$tx_in_str $(get_all_input_utxos_at $i)"
    done

    # Build the string of signing key files
    for i in $(seq $1 $2)
    do
        # signing_keys_str=$signing_keys_str' --signing-key-file '$i'.skey'
        signing_keys_str="$signing_keys_str --signing-key-file $preDir/$i.skey"
    done

    # Transaction
    $cli transaction build                      \
        --babbage-era                           \
        $MAGIC                                  \
        $tx_in_str                              \
        --change-address $(cat $preDir/$3.addr) \
        --out-file $txBody

    $cli transaction sign      \
        --tx-body-file $txBody \
        $signing_keys_str      \
        $MAGIC                 \
        --out-file $txSigned

    submit_tx
}


# Helper function that returns how much Lovelace is held in the first UTxO of
# the given wallet address.
#
# Takes 1 argument:
#   1. User's wallet address file.
get_first_lovelace_count_of() {
    echo `$cli query utxo            \
        --address $(cat $1)          \
        $MAGIC                       \
        | sed 1,2d                   \
        | awk 'FNR == 1 {print $3}'`
}


# Given a wallet, a script, and other arguments, this function constructs,
# signs and submits a transaction for interacting with a smart contract.
#
# Takes 7 arguments:
#   1. User's wallet address file,
#   2. User's wallet signing key file,
#   3. The script file,
#   4. Script's current datum JSON file,
#   5. Redeemer's JSON file for the intended endpoint,
#   6. Amount that should be added to script's holding,
#   7. Updated datum of the script after the transaction.
interact_with_smart_contract() {

    # Build script address from a script, if script address does not exist. 
    # The address name is the same as the script, except its extension is changed to .addr
    # script_addr=$($3 | sed "s/\..*/.addr/") # Name is $3 with its ext changed to .addr
    # Safety check to not overwrite any existing file, and to avoid rebuilding if already built.
    if [ -f $script_addr ]
    then
    echo "Using the script address $script_addr, which already exists. If this is incorrect, then move, rename, or change $script_addr and run again."
    else
    plutus_script_to_address # $3 $script_addr # Builds script file address
    fi
    script_addr=$scriptAddressFile

    users_utxo=$(get_first_utxo_of $1)
    script_holding=$(get_first_lovelace_count_of $script_addr)
    extra_output=$(expr $6 + $script_holding)

    $cli transaction build                        \
        --tx-in $users_utxo                       \
        --tx-in $(get_first_utxo_of $script_addr) \
        --tx-in-script-file $3                    \
        --tx-in-datum-file $4                     \
        --tx-in-redeemer-file $5                  \
        --tx-in-collateral $users_utxo            \
        --tx-out $(cat $1)+$extra_output          \
        --tx-out-datum-embed-file  $7             \
        --change-address $(cat $1)                \
        --protocol-params-file protocol.json      \
        --out-file tx.raw                         \
        $MAGIC

    $cli transaction sign                         \
        --tx-body-file tx.raw                     \
        --signing-key-file $2                     \
        $MAGIC                                    \
        --out-file tx.signed

    $cli transaction submit                       \
        $MAGIC                                    \
        --tx-file tx.signed
}


# Generate a fresh protocol parametsrs JSON file.
generate_protocol_params() {
    $cli query protocol-parameters $MAGIC --out-file $protocolsFile
}


# Takes at least 1 argument:
#   1. The signing key file.
#   *. Any additional signing key files.
sign_tx_by() {
    signArg=""
    for i in $@; do
      signArg="$signArg --signing-key-file $i"
    done
    $cli transaction sign      \
        --tx-body-file $txBody \
        $signArg               \
        $MAGIC                 \
        --out-file $txSigned
}


# Submits $txSigned to the chain.
submit_tx() {
    $cli transaction submit \
        $MAGIC              \
        --tx-file $txSigned
}

# Runs qvf-cli cmds with nix-shell from outside nix-shell
# Uses a HERE doc to do this
# PARAMS: $1=donor_pkh_file $2=receiver_pkh_file $3=lovelace_amt $4=current_datum
update_datum_donate_qvf_cli() {

    # Edit these: ---------
    path_to_plutus_apps=$HOME/plutus-apps
    path_to_quadratic_voting=$HOME/quadraticvoting
    current_path=$(pwd)
    # ---------------------

    donor_pkh_file=$1
    receiver_pkh_file=$2
    lovelace_amt=$3

    # Make the script to execute within the nix-shell with a HERE DOC
    cat > "$path_to_plutus_apps"/update-datum.sh <<EOF
#! /usr/bin/env nix-shell
#! nix-shell -i sh

cd $path_to_quadratic_voting
. scripts/test_remote.sh
donorsPKH=$(cat $current_path/$1)
obj=\$(find_utxo_with_project \$scriptAddr "\$policyId\$tokenName" \$(cat $2))
len=\$(echo \$obj | jq length)
if [ \$len -eq 0 ]; then
    echo "FAILED to find the project."
else
    currDatum="$current_path/curr.datum"
    updatedDatum="$current_path/updated.datum"
    action="$current_path/donate.redeemer"
    obj=\$(echo \$obj | jq .[0])
    utxo=\$(echo \$obj | jq .utxo)
    datumHash=\$(echo \$obj | jq .datumHash)
    datumValue=\$(echo \$obj | jq .datumValue)
    lovelace=\$(echo \$obj | jq .lovelace | jq tonumber)
    newLovelace=\$(expr \$lovelace + $3)
    echo \$lovelace
    echo \$newLovelace > newLovelace
    echo \$datumValue > \$currDatum
    $qvf donate $(cat $donor_pkh_file) $(cat $receiver_pkh_file) \$lovelace_amt \$current_datum out_datum.json out_redeem.json
    $qvf pretty-datum \$(cat \$updatedDatum)
    cp out_datum.json "$current_path" # Optional, see how workflow works out
    cp out_redeem.json "$current_path" # Optional, see how workflow works out
    cp newLovelace "$current_path" # Optional, see how workflow works out
    echo "DONE."
fi
exit # Exit nix-shell
EOF
    # Run the HERE file commands in nix-shell
    cd "$path_to_plutus_apps"
    chmod +x update-datum.sh
    ./update-datum.sh
    cd "$current_path"
}

# WIP
# cardano-cli transaction cmd to donate
# PARAMS: $1=donorAddrFile $2=donorSKeyFile $3=utxoFromDonor $4=utxoAtScript $5=currentDatum $6lovelace_amt_script $7=lovelace_amt_donation
donate_to_smart_contract() {
    # Edit these: ---------
    authAsset=62a65c6ce2c30f7040f0bc8cc5eb5f3f07521757125a03d743124a54.517561647261546f6b656e
    scriptAddr=addr_test1wpl9c67dav6n9gjxlyafg6dmsql8tafy3pwd3fy06tu26nqzphnsx
    scriptFile="qvf.plutus"      # The Plutus script file (qvf.plutus)
    donorAddrFile="$1"   # The file that contains donor's wallet address.
    donorSKeyFile="$2"   # The file that contains donor's signing key.
    #utxoFromDonor="efd9d27b0ba008b8495aee6d4d01c5ebe0c281b55a623a31fe0b631c6365cb22"   # A UTxO from donor's wallet that has enough ADA for donation, tx fee and collateral.
    utxoFromDonor="$3"   # A UTxO from donor's wallet that has enough ADA for donation, tx fee and collateral.
    utxoAtScript="$4"    # The UTxO at the script with the current datum attached.
    currentDatum="$5"    # JSON file containing current state of the contract, about to be updated.
    newDatum="out_datum.json"        # JSON file containing updated state of the contract.
    redeemer="out_redeem.json"        # JSON file containing the `Donate` redeemer.
    lovelace_amt_script="$6"
    lovelace_amt_donation="$7"
    newLovelaceCount=$(expr lovelace_amt_script + lovelace_amt_donation) # Current Lovelace count of $utxoAtScript, plus the donated amount.
    # ---------------------

    # Construct the transaction:
    $cli transaction build --babbage-era $MAGIC                            \
        --tx-in $utxoFromDonor                                             \
        --tx-in-collateral $utxoFromDonor                                  \
        --tx-in $utxoAtScript                                              \
        --tx-in-datum-file $currentDatum                                   \
        --tx-in-script-file $scriptFile                                    \
        --tx-in-redeemer-file $redeemer                                    \
        --tx-out "$scriptAddr + $newLovelaceCount lovelace + 1 $authAsset" \
        --tx-out-datum-embed-file $newDatum                                \
        --change-address $(cat $donorAddrFile)                             \
        --protocol-params-file protocol.json                               \
        --out-file tx.unsigned

    # Sign the transaction:
    $cli transaction sign $MAGIC          \
        --tx-body-file tx.unsigned        \
        --signing-key-file $donorSKeyFile \
        --out-file tx.signed

    # Submit the transaction:
    $cli transaction submit $MAGIC --tx-file tx.signed

}
