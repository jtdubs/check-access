#!/bin/bash

set -euo pipefail

TMP=$(mktemp -d)

log()
{
  TIME=$(date)
  MSG=$1
  echo $MSG
  echo $TIME: $MSG >> $TMP/output
}

print_entry()
{
  local FILE=$1
  if [ -L "$FILE" ]
  then
	local TARGET=$(readlink -f $FILE)
	local FILE_INFO=$(stat --format="%A,%U,%G,%n" "$FILE")
	echo "$FILE_INFO,$TARGET"
	stat --format="%A,%U,%G,%n," "$TARGET"
  else
	stat --format="%A,%U,%G,%n," "$FILE"
  fi
}

find_entries()
{
  local FIND_TEST=$1
  local OUT_FILE=$2

  echo perms,owner,group,path,target > $OUT_FILE
  find -L $ROOT $FIND_TEST -print | while read FILE; do print_entry $FILE; done >> $OUT_FILE
}

set +u
if [ -z "$1" ]
then
  log "Usage: $0 [userid] [root]"
  exit 1
fi

USER="$1"
ROOT="$2"
set -u

if [ -z "$ROOT" ]
then
  ROOT="/"
else
  ROOT=$(realpath $ROOT)
fi

log "Analyzing access of '$USER' to '$ROOT'..."

if ! id -un "$USER" > /dev/null
then
  log "User '$USER' not found!"
  exit 1
fi

MEMBERSHIPS=$(id -Gn $USER)

GROUP_TEST=""
for GROUP in $MEMBERSHIPS
do
  if [ -z "$GROUP_TEST" ]
  then
    GROUP_TEST="( -group $GROUP"
  else
    GROUP_TEST="$GROUP_TEST -o -group $GROUP"
  fi
done
GROUP_TEST="$GROUP_TEST )"

log "Group memberships: $MEMBERSHIPS"

log "Looking for world-writable dirs..."
find_entries "-type d -perm -a+w" $TMP/world-writable-dirs.csv

log "Looking for world-writable files..."
find_entries "-type f -perm -a+w" $TMP/world-writable-files.csv

log "Looking for user-writable dirs..."
find_entries "-type d -user $USER -perm -u+w" $TMP/user-writable-dirs.csv

log "Looking for user-writable files..."
find_entries "-type f -user $USER -perm -u+w" $TMP/user-writable-files.csv

log "Looking for group-writable dirs..."
find_entries "-type d $GROUP_TEST -perm -g+w" $TMP/group-writable-dirs.csv

log "Looking for group-writable files..."
find_entries "-type f $GROUP_TEST -perm -g+w" $TMP/group-writable-files.csv

log "Looking for accessible setuid files..."
find_entries "-type f -perm -a+x -perm -u+s" $TMP/group-writable-files.csv

log "Looking for accessible setgid files..."

HOST=$(hostname)
OUTPUT="$HOST-$USER-access.tgz"
log "Packaging output info '$OUTPUT'..."
tar -zcf $OUTPUT -C $TMP .
