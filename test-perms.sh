#!/bin/bash

# exit on failed commands or undefined variables 
set -euo pipefail

# make a temp folder for output files
OUTDIR=$(mktemp -d)


#
# log(MSG) - print a message and log it with a timestamp
#
# MSG - the message to print
#
log()
{
  local TIME=$(date)
  local MSG=$1

  echo $MSG
  echo $TIME: $MSG >> "$OUTDIR/output.log"
}


#
# print_entry(FILE) - print info about a file
#
# FILE - the file to print info about
#
print_entry()
{
  local FILE=$1

  # get the file's permissions, user, group and name
  local FILE_INFO=$(stat --format="%A,%U,%G,%n," "$FILE")

  # if it's a symlink
  if [ -L "$FILE" ]
  then
	# append the target of the symlink
	local TARGET=$(readlink -f $FILE)
	FILE_INFO="$FILE_INFO$TARGET"
  fi

  echo "$FILE_INFO"
}


#
# Parse and sanity-check command-line parameters
#

# temporarily disable unbound variable checking so we can look for command-line args
set +u

# ensure userid is specified
if [ -z "$1" ]
then
  log "Usage: $0 [userid] [root]"
  exit 1
fi

# assign command-line args to variables
USER="$1"
ROOT="$2"

# re-enable unbound variable checking
set -u

# if root wasn't specified
if [ -z "$ROOT" ]
then
  # default to /
  ROOT="/"
else
  # otherwise, resolve relative paths
  ROOT=$(realpath $ROOT)
fi

# if user doesn't exist
if ! id -un "$USER" > /dev/null
then
  # fail
  log "User '$USER' not found!"
  exit 1
fi


#
# Perform the access check
#

log "Analyzing access of '$USER' to '$ROOT'..."

# capture user id and group membership info
echo $(id) > "$OUTDIR/id.log"

# create output CSV files with appropriate header
echo perms,owner,group,path,target | tee "$OUTDIR/writable.csv" "$OUTDIR/runnable.csv" "$OUTDIR/setuid.csv" "$OUTDIR/setgid.csv" > /dev/null

# disable exit-on-error in case we hit access denied issues
set +e

# for each file or directory under ROOT
find -L $ROOT \( -type f -o -type d \) -print 2> "$OUTDIR/errors.log" | while read FILE; do
  # if writable
  if [ -w "$FILE" ]; then print_entry "$FILE" >> "$OUTDIR/writable.csv"; fi

  # if file that's executable
  if [ -f "$FILE" -a -x "$FILE" ]; then print_entry "$FILE" >> "$OUTDIR/runnable.csv"; fi

  # if file is (writable or executable) and setgid
  if [ -f "$FILE" -a \( -w "$FILE" -o -x "$FILE" \) -a -g "$FILE" ]; then print_entry "$FILE" >> "$OUTDIR/setgid.csv"; fi

  # if file is (writable or executable) and setuid
  if [ -f "$FILE" -a \( -w "$FILE" -o -x "$FILE" \) -a -u "$FILE" ]; then print_entry "$FILE" >> "$OUTDIR/setuid.csv"; fi
done

# re-enable exit-on-error
set -e


#
# Capture scan results
#

HOST=$(hostname)
OUTPUT_FILE="$USER-$HOST.tgz"

log "Packaging output files into '$OUTPUT_FILE'..."

# tar up the output files into USER-HOST.tgz
tar -czf $OUTPUT_FILE -C "$OUTDIR" .
