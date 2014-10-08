#!/bin/bash

# how many indizes should be kept online at elasticsearch
KEEP_ONLINE=60

# how many indizes shoud be kept as closed
KEEP_CLOSED=30

# how many indizes should be archived
KEEP_ARCHIVED=275

# (in total: 356 indizes are available)

# name of the indexes
INDEX_NAME_GREP=logstash

# elasticsearch host
ES_HOST=localhost:9200

# archive directory
ARCHIVE_DIR=/var/backup/elasticsearch

# curl log file
CURL_LOG=/var/log/elasticRotorCurl.log

#### END OF SETTINGS

INDEX_LIST=`curl -s http://$ES_HOST/_cat/indices?h=i | grep $INDEX_NAME_GREP | sort -r`
INDEX_LIST=$INDEX_LIST`curl -s "http://$ES_HOST/_cluster/state/blocks?pretty=true" | grep -v \"index\" | sort -r | awk -F\" {'print $2'} | grep $INDEX_NAME_GREP`

INDEX_COUNT=`echo "$INDEX_LIST" | wc -l`
INDEX_LIST_ONLINE=`echo "$INDEX_LIST" | sed -n "1,${KEEP_ONLINE}p"`
INDEX_LIST_CLOSED=`echo "$INDEX_LIST" | sed -n "$((${KEEP_ONLINE}+1)),$((${KEEP_ONLINE}+${KEEP_CLOSED}))p"`
INDEX_LIST_ARCHIVED=`echo "$INDEX_LIST" | sed -n "$((${KEEP_ONLINE}+${KEEP_CLOSED}+1)),$((${KEEP_ONLINE}+${KEEP_CLOSED}+${KEEP_ARCHIVED}))p"`
INDEX_LIST_PURGED=`echo "$INDEX_LIST" | tail -n +$((${KEEP_ONLINE}+${KEEP_CLOSED}+${KEEP_ARCHIVED}+1))`

### CLOSING INDICES

echo "Closing Indices..."

for i in $INDEX_LIST_CLOSED; do

  echo -n "Closing Index $i ... "
  CURL_CMD="$ES_HOST/$i/_close"
  HTTP_RESPONSE=`curl --write-out "%{http_code}" --silent --output $CURL_LOG -XPOST ${CURL_CMD}`

  if [ "$HTTP_RESPONSE" -eq "200" ]
  then
    echo " Done."
  else
    echo " Got error $HTTP_RESPONSE. Exiting."
    exit 0
  fi

done;

### ARCHIVING INDICES

echo "Archive indices..."

for i in $INDEX_LIST_ARCHIVED; do

  echo -n "Opening Index $i for archiving... "
  CURL_CMD="$ES_HOST/$i/_open"
  HTTP_RESPONSE=`curl --write-out "%{http_code}" --silent --output $CURL_LOG -XPOST ${CURL_CMD}`

  if [ "$HTTP_RESPONSE" -eq "200" ]
  then
    echo " Done."
  else
    echo " Got error $HTTP_RESPONSE. Exiting."
    exit 0
  fi

  echo -n "Waiting... "
  CURL_CMD="$ES_HOST/$i/_status?pretty=1"
  while [ "`curl -s -XGET ${CURL_CMD} | grep STARTED | wc -l`" -eq "0" ]; do
    sleep 1
  done;
  echo " done."

  echo -n "Archiving Index $i ..."

  CURL_CMD="$ES_HOST/$i/_export?path=$ARCHIVE_DIR/$i.tar.gz"
  HTTP_RESPONSE=`curl --write-out "%{http_code}" --silent --output $CURL_LOG -XPOST ${CURL_CMD}`

  if [ "$HTTP_RESPONSE" -eq "200" ]
  then
    echo " Queued."
  else
    echo " Got error $HTTP_RESPONSE. Exiting."
    exit 0
  fi
done;

sleep 3
echo -n "Waiting for archiving to complete... "

CURL_CMD="$ES_HOST/_export/state?pretty=1"
while [ "`curl -s -XGET ${CURL_CMD} | wc -l`" -ne "3" ]; do
  sleep 1
done;

echo " done."

### DELETE ARCHIVED INDICES

echo "Delete just archived indices..."

for i in $INDEX_LIST_ARCHIVED; do

  echo -n "Deleting Index $i ..."
  CURL_CMD="$ES_HOST/$i/"
  HTTP_RESPONSE=`curl --write-out "%{http_code}" --silent --output $CURL_LOG -XDELETE ${CURL_CMD}`

  if [ "$HTTP_RESPONSE" -eq "200" ]
  then
    echo " Done."
  else
    echo " Got Error $HTTP_RESPONSE. Exiting."
    exit 0
  fi
done;


### DELETE PURGED INDICES

echo "Delete Purged Indices..."

for i in $INDEX_LIST_PURGED; do

  echo -n "Deleting Index $i ..."
  CURL_CMD="$ES_HOST/$i/"
  HTTP_RESPONSE=`curl --write-out "%{http_code}" --silent --output $CURL_LOG -XDELETE ${CURL_CMD}`

  if [ "$HTTP_RESPONSE" -eq "200" ]
  then
    echo " Done."
  else
    echo " Got Error $HTTP_RESPONSE. Exiting."
    exit 0
  fi
done;


### DELETE ARCHIVES

ARCHIVE_FILES_DELETE=`ls -1 $ARCHIVE_DIR/*.gz | sort -r | tail -n +$KEEP_ARCHIVED`

for i in $ARCHIVE_FILES_DELETE; do
  echo -n "Delete Archive $i ..."
  #rm -f $ARCHIVE_DIR/$i
  echo " Done."
done;

echo "Completed."

