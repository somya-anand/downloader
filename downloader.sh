#!/bin/bash

function usage {
  echo -e "Usage:\n\t`basename $0` <url> [split size (dafault: 128mb)]"
  exit 1
}
 
#Cleanup on kill
function clean {
  echo 'Failing: cleaning up...'
  kill -0 $$
  rm /tmp/$FILENAME.* 2> /dev/null
  echo "Download failed!"
  exit 1 
}
 
#Check parameters
if [ ! "$1" ];then
  echo "Where's the URL?"
  usage
fi
 
SPLITSIZE=${2:-${downloader_chunk_size:-128}}
SPLITSIZE=$(($SPLITSIZE * 1024 * 1024))

URL=$1

FILENAME="`basename $URL`"

echo 'get file size...'
SIZE="`curl -qLI $URL 2> /dev/null|awk '/Length/ {print $2}'|grep -o '[0-9]*'`"
SIZE=${SIZE:-1} 

SPLITNUM=$((${SIZE:-0}/$SPLITSIZE))

[ $SPLITNUM -ne 0 ] || SPLITNUM=1

START=0
CHUNK=$((${SIZE:-0}/$SPLITNUM))
END=$CHUNK

OUT_DIR=${downloader_output_dir:-$HOME/Downloads}
 
#Trap ctrl-c
trap 'clean' SIGINT SIGTERM
 
echo 'Testing file splitness...'
#Test splitness
curl -Lm 2 --range 0-0 $URL 2> /dev/null | read line
OUT=${#line}

echo '... got the results ... just verifying ' ${OUT}
#Check out
case ${OUT} in
0)  clean; echo 'exiting...';; #Curl error
1)  ;; #Got a byte
*)  echo 'Server does not spit...';SPLITNUM=1;; #Got more than asked for
esac
 
echo 'launching downloader threads...'
#Invoke curls
for PART in `eval echo {1..$SPLITNUM}`;do
  curl --ftp-pasv -Lo "/tmp/$FILENAME.$PART" --range $START-$END $URL 2> /dev/null &
  START=$(($START+$CHUNK+1))
  END=$(($START+$CHUNK))
done
 
TIME=$((`date +%s`-1))
function calc {
 GOTSIZE=$((`eval ls -l "/tmp/$FILENAME".{1..$SPLITNUM} 2> /dev/null|awk 'BEGIN{SUM=0}{SUM=SUM+$5}END{print SUM}'`))
 TIMEDIFF=$(( `date +%s` - $TIME ))
 RATE=$(( ($GOTSIZE / $TIMEDIFF)/1024 ))
 PCT=$(( ($GOTSIZE*100) / $SIZE ))
}

#Wait for all parts to complete while spewing progress
while jobs | grep -q Running;do
 calc
 echo -n "Downloading $FILENAME in $SPLITNUM parts: $(($GOTSIZE/1048576)) / $(($SIZE/1048576)) mb @ $(($RATE)) kb/s ($PCT%).    "
 tput ech ${#SIZE}
 tput cub 1000
 sleep 1
done
calc
echo "Downloading $FILENAME in $SPLITNUM parts: $(($GOTSIZE/1048576)) / $(($SIZE/1048576)) mb @ $(($RATE)) kb/s ($PCT%).    "

#Check if file name exists
FILENAME2=$FILENAME
if([ -f "$OUT_DIR/$FILENAME2" ]) then
  read -p "$FILENAME2 already exists in $OUT_DIR. Do you want to overwrite? [n/y] " opt
  case $opt in
    [Yy]* ) break;;
    *)
      i=2
      while [[ -f "$OUT_DIR/$FILENAME2" ]]; do
        FILENAME2="${FILENAME%.*}($i).${FILENAME#*.}"
        i=$(($i+1))
      done
  esac
fi

#Join all the parts
eval cat "/tmp/$FILENAME".{1..$SPLITNUM} > "/$OUT_DIR/$FILENAME2"
echo "Download completed! Check file $FILENAME2 in $OUT_DIR."
rm /tmp/$FILENAME.* 2> /dev/null
