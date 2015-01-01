#!/bin/bash

if [ -f ".tmp/blocks.out" ]; then
  rm -rvf .tmp/blocks.out
fi

function findBlockages(){
  #this function will find any process that has been blocked.
  #the sole purpose of this diagnostic is to find the highest occuring blocks, typically caused by thread unsafe code.
  #the results printed by this function will show which line of code is blocked, what that block is waiting on aswell as how many instances have occured.
  find stacks/ -type f -name "stack-*.out" | while read af; do
    echo "Processing Stack $af"
    fileStamp=$(echo "$af" | sed -e 's/.*-//' -e 's/\..*//')
    cat "$af" | grep BLOCK -A 10 -B 1 | sed -e ':a;N;$!ba;s/\n/~LINEBREAK~/g' -e 's/--/\n/g' | while read aline; do
      echo "Processing blockage..."
      curBlock=$(echo "$aline" | sed 's/~LINEBREAK~/\n/g' | grep -v "^$")
      threadID=$(echo "$curBlock" | head -1 | awk '{print $1}')
      stuckOn=$(echo "$curBlock" | head -3 | tail -1 | awk '{print $2}')
      waitingOnId=$(echo "$curBlock" | head -4 | tail -1 | awk '{print $5}' | grep -o "[a-fx0-9]*")
      waitingOn=$(echo "$curBlock" | head -4 | tail -1 | sed -e 's/.* //' -e 's/)//')
      blockCause=$(cat "$af" | grep "locked <$waitingOnId" -B 200 | sed -e ':a;N;$!ba;s/.*\n\n//g' | head -4 | tail -1 | awk '{print $2}')
      echo "$fileStamp,$threadID,$blockCause,$waitingOn,$stuckOn" >> .tmp/blocks.out
    done
  done
}

function findLongRunning(){
  echo "1" >/dev/null
}

function printReport(){
  echo "----------------------------------------"
  echo "Top occuring blockages..."
  echo ""
  cat .tmp/blocks.out | awk 'BEGIN{FS=","}{print $2 " " $5}' | sort -u | awk '{print $2}' | sort | uniq -c | sort -n | tac
  echo ""
  echo "Top occuring blockages causes..."
  echo ""
  cat .tmp/blocks.out | awk 'BEGIN{FS=","}{print $2 " " $3}' | sort -u | awk '{print $2}' | sort | uniq -c | sort -n | tac
  echo ""
  echo "Longest blocked processes..."
  echo ""
  i=0; cat .tmp/blocks.out | awk 'BEGIN{FS=","}{print $2 " " $1}' | sort | while read aline; do if [ "$lastID" != "$(echo "$aline" | awk '{print $1}')" -a "$i" -gt "0" ]; then echo "$lastID $ID_START_TIME $ID_LAST_TIME $(($ID_LAST_TIME-$ID_START_TIME))"; ID_START_TIME=$(echo "$aline" | awk '{print $2}'); elif [ "$i" == "0" ]; then ID_START_TIME=$(echo "$aline" | awk '{print $2}'); fi; ((i++)); ID_LAST_TIME=$(echo "$aline" | awk '{print $2}'); lastID="$(echo "$aline" | awk '{print $1}')"; if [ "$i" == "20" ]; then echo "$lastID $ID_START_TIME $ID_LAST_TIME $(($ID_LAST_TIME-$ID_START_TIME))"; fi; done | sort -n -k4 | while read athread; do
    threadName=$(echo "$athread" | awk '{print $1}')
    blockDuration=$(echo "$athread" | awk '{print $4}')
    blockStart=$(date -d @$(echo "$athread" | awk '{print $2}') +"%D %T")
    blockEnd=$(date -d @$(echo "$athread" | awk '{print $3}') +"%D %T")
    echo "Thread: $threadName was blocked for $blockDuration secconds, from: $blockStart to: $blockEnd"
  done | nl
  echo ""
  echo "----------------------------------------"
  echo "Blockage details..."
  echo "----------------------------------------"
  echo ""
  cat .tmp/blocks.out | awk 'BEGIN{FS=","}{print $2 " " $5}' | sort -u | awk '{print $2}' | sort | uniq -c | sort -n | tac | awk '{print $2}' | while read aline; do
    echo "    Blockage: $aline, was caused by: "
    cat .tmp/blocks.out | grep "$aline" | awk 'BEGIN{FS=","}{print $3 " locking a resource for... " $4}' | sort | uniq -c | sort -n | tac
    echo ""
  done
}

findBlockages
findLongRunning

printReport | tee -a "reports/Report-$(date +"%Y%m%d-%H%M%S").txt"

