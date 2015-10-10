#!/bin/bash

STD_EX_PREP="TP-Processor|ajp-bio-8009-exec-|ajp-bio-8010-exec-"
CUSTOM_EX_PREP="(hybrisHTTP|$STD_EX_PREP)"
MAX_THREADS="450"

read -p "Max Threads: " MAX_THREADS

function maxedOutThreads(){
	if [ -f ".tmp/maxed.out" ]; then
	  rm -rvf .tmp/maxed.out
	fi
	find stacks/ -type f -name "stack-*.out" | while read af; do
		threadCount=$(cat "$af" | egrep "^\"$CUSTOM_EX_PREP" | wc -l)
		if [ "$threadCount" -gt "$(($MAX_THREADS-20))" ]; then
			fileStamp=$(echo "$af" | sed -e 's/.*-//' -e 's/\..*//')
			echo "Thread count warning at $(date -d @"$fileStamp" +"%D +%T") , thread count for $CUSTOM_EX_PREP was $threadCount" >> .tmp/maxed.out
		fi 
	done
}

function normalizeStacks(){
	if [ -f ".tmp/states.out" ]; then
	  rm -rvf .tmp/states.out
	fi
	#Stacks2csv
	find stacks/ -type f -name "stack-*.out" | while read af; do
		echo "Normalizing... $af"
		fileStamp=$(echo "$af" | sed -e 's/.*-//' -e 's/\..*//')
		cat "$af" | grep "^\"" | sed -e 's/^"//' -e 's/".*//' | sort -n | while read athread; do
			atREG=$(echo "$athread" | sed -e 's/\[/\\[/' -e 's/\]/\\]/')
			procy=$(cat "$af" | grep "$atREG" -A 2 | tail -1 | sed 's/.*at //')
			procyState=$(cat "$af" | grep "$atREG" -A 1 | tail -1 | awk '{print $2}')
			if [ "$procyState" == "WAITING" ]; then
				testSpare=$(cat "$af" | grep "\"$atREG\"" -A 5 | egrep "(org.apache.tomcat.util.net.JIoEndpoint|a java.util.concurrent.locks.AbstractQueuedSynchronizer|org.apache.tomcat.util.threads.ThreadPool\\\$ControlRunnable)")
				if [ -n "$testSpare" ]; then
					procyState="SPARE_WAITING"
				fi
			elif [ "$procyState" == "RUNNABLE" ]; then
				testAJPWAIT=$(cat "$af" | grep "\"$atREG\"" -A 8 | egrep "(org.apache.coyote.ajp.AjpProcessor.read)")
				if [ -n "$testAJPWAIT" ]; then
					procyState="AJP_WAITING"
				fi				
			fi
			if [ -n "$procy" -a -n "$procyState" ]; then
				echo "$fileStamp,$procyState,$athread,$procy" >> .tmp/states.out
			fi
		done
	done
}

function findBlockages(){
	if [ -f ".tmp/blocks.out" ]; then
	  rm -rf .tmp/blocks.out
	fi
	if [ -f ".tmp/top.block.cause" ]; then
	  rm -rf .tmp/top.block.cause
	fi
	if [ -f ".tmp/top.blocked.procs" ]; then
	  rm -rf .tmp/top.blocked.procs
	fi
	if [ -f ".tmp/top.blocks.details" ]; then
	  rm -rf .tmp/top.blocks.details
	fi
	if [ -f ".tmp/top.blocks.duration" ]; then
	  rm -rf .tmp/top.blocks.duration
	fi

	cat .tmp/states.out | grep ,BLOCKED, | awk 'BEGIN{FS=","}{print $3}' | sort -u | while read bNode; do
		echo "Processing blockages in thread $bNode"
		cat .tmp/states.out | grep "$bNode" | sort -n | sed -e 's/,RUNNABLE,\(.*\)/,RUNNABLE,\1\n~ENDBLOCK~/g' | sed  -e ':amoo;N;$!bamoo;s/\n/~LINEBREAK~/g' -e 's/~ENDBLOCK~/\n/g' | sed 's/^~LINEBREAK~//' | while read ablock; do
			i=1
			#to process all blocks head must be removed and times augmented to thread level
			echo "$ablock" | sed 's/~LINEBREAK~/\n/g' | grep ",BLOCKED," | head -1 | while read aline; do
				fileStamp=$(echo "$aline" | awk 'BEGIN{FS=","}{print $1}')
				#echo "Processing blockage at $fileStamp in thread \"$bNode\""
				#echo "DEBUG:1001"
				threadID=$(echo "$aline"WAITING | awk 'BEGIN{FS=","}{print $3}')
				blockageStart=$(echo "$aline" | awk 'BEGIN{FS=","}{print $1}')
				blockedTask=$(echo "$aline" | sed 's/~LINEBREAK~/\n/g' | grep ",BLOCKED," -A 1 | head -1 | awk 'BEGIN{FS=","}{print $4}')
				blockageEnd=$(echo "$ablock" | sed 's/~LINEBREAK~/\n/g' | grep ",BLOCKED," -A 1 | tail -1 | awk 'BEGIN{FS=","}{print $1}')
				waitingOn=$(cat "stacks/stack-$fileStamp.out" | grep "^\"$threadID\"" -A 3 | tail -1 | grep "waiting on")
				waitingToLock=$(cat "stacks/stack-$fileStamp.out" | grep "^\"$threadID\"" -A 3 | tail -1 | grep "waiting to lock")
				parkingToWaitFor=$(cat "stacks/stack-$fileStamp.out" | grep "^\"$threadID\"" -A 3 | tail -1 | grep "parking to wait for")
				if [ -n "$waitingOn" ]; then
					waitingOnId=$(echo "$waitingOn" | grep -o "[0-9]x[0-9a-f]*")
					resourceLockedBy=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingOnId>" -B 1|head -1|awk '{print $2}')
					desiredResource=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingOnId>"|head -1|sed 's/.*(/(/')
				elif [ -n "$waitingToLock" ]; then
					waitingToLockId=$(echo "$waitingToLock" | grep -o "[0-9]x[0-9a-f]*")
					resourceLockedBy=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingToLockId>" -B 1|head -1|awk '{print $2}')
					desiredResource=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingToLockId>"|head -1|sed 's/.*(/(/')
				elif [ -n "$parkingToWaitFor" ]; then
					parkingToWaitForId=$(echo "$parkingToWaitFor" | grep -o "[0-9]x[0-9a-f]*")
					resourceLockedBy=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$parkingToWaitForId>" -B 1|head -1|awk '{print $2}')
					if [ -z "$resourceLockedBy" ]; then
						resourceLockedBy=$(echo "$parkingToWaitFor" | sed -e 's/.*(//' -e 's/)$//')
					fi
				else
					waitingOnId=""
					resourceLockedBy=""
				fi
				echo "$fileStamp,$threadID,$blockedTask,$resourceLockedBy,$desiredResource" >> .tmp/blocks.out
				((i++))
			done
		done
	done

	if [ -f ".tmp/blocks.out" ]; then
		cat .tmp/blocks.out | awk 'BEGIN{FS=","}{print $3}' | sort | uniq -c | sort -n | tac > .tmp/top.blocked.procs
		cat .tmp/blocks.out | awk 'BEGIN{FS=","}{print $4}' | sort | sed 's/^$/Unexplained Mystery/' | uniq -c | sort -n | tac > .tmp/top.block.cause
		i=0; cat .tmp/blocks.out | awk 'BEGIN{FS=","}{print $2 " " $1}' | sort | while read aline; do if [ "$lastID" != "$(echo "$aline" | awk '{print $1}')" -a "$i" -gt "0" ]; then echo "$lastID $ID_START_TIME $ID_LAST_TIME $(($ID_LAST_TIME-$ID_START_TIME))"; ID_START_TIME=$(echo "$aline" | awk '{print $2}'); elif [ "$i" == "0" ]; then ID_START_TIME=$(echo "$aline" | awk '{print $2}'); fi; ((i++)); ID_LAST_TIME=$(echo "$aline" | awk '{print $2}'); lastID="$(echo "$aline" | awk '{print $1}')"; if [ "$i" == "20" ]; then echo "$lastID $ID_START_TIME $ID_LAST_TIME $(($ID_LAST_TIME-$ID_START_TIME))"; fi; done | sort -n -k4 | while read athread; do
			threadName=$(echo "$athread" | awk '{print $1}')
			blockDuration=$(echo "$athread" | awk '{print $4}')
			blockStart=$(date -d @$(echo "$athread" | awk '{print $2}') +"%D %T")
			blockEnd=$(date -d @$(echo "$athread" | awk '{print $3}') +"%D %T")
			echo "Thread: $threadName was blocked for $blockDuration secconds, from: $blockStart to: $blockEnd"
		done | tac | head -n 25 | nl > .tmp/top.blocks.duration
		cat .tmp/blocks.out | awk 'BEGIN{FS=","}{print $3}' | sort | uniq -c | sort -n | tac | sed 's/.*[0-9] //' | while read aline; do
			echo "    Blockage: $aline, was caused by: "
			cat .tmp/blocks.out | grep "$aline" | awk 'BEGIN{FS=","}{print $4 " locking the resource \"" $5 "\""}'|sort|uniq -c|sort -n|tac
			echo ""
		done > .tmp/top.blocks.details
	fi
}

function findWait(){
	if [ -f ".tmp/waits.out" ]; then
	  rm -rvf .tmp/waits.out
	fi
	if [ -f ".tmp/top.waits.cause" ]; then
	  rm -rvf .tmp/top.waits.cause
	fi
	if [ -f ".tmp/top.waits.details" ]; then
	  rm -rvf .tmp/top.waits.details
	fi
	if [ -f ".tmp/top.waits.duration" ]; then
	  rm -rvf .tmp/top.waits.duration
	fi
	if [ -f ".tmp/top.waits.procs" ]; then
	  rm -rvf .tmp/top.waits.procs
	fi

	cat .tmp/states.out | grep ,WAITING, | awk 'BEGIN{FS=","}{print $3}' | sort -u | while read bNode; do
		echo "Processing waits in thread $bNode"
		cat .tmp/states.out | grep "$bNode" | sort -n | sed -e 's/,RUNNABLE,\(.*\)/,RUNNABLE,\1\n~ENDBLOCK~/g' | sed  -e ':amoo;N;$!bamoo;s/\n/~LINEBREAK~/g' -e 's/~ENDBLOCK~/\n/g' | sed 's/^~LINEBREAK~//' | grep ",WAITING," | while read ablock; do
			i=1
			#to process all waits head must be removed and times augmented to thread level
			echo "$ablock" | sed 's/~LINEBREAK~/\n/g' | grep ",WAITING," | head -1 | while read aline; do
				fileStamp=$(echo "$aline" | awk 'BEGIN{FS=","}{print $1}')
				#echo "Processing wait at $fileStamp in thread \"$bNode\""
				#echo "DEBUG:1002"
				threadID=$(echo "$aline" | awk 'BEGIN{FS=","}{print $3}')
				blockageStart=$(echo "$aline" | awk 'BEGIN{FS=","}{print $1}')
				blockedTask=$(echo "$aline" | sed 's/~LINEBREAK~/\n/g' | grep ",WAITING," | head -1 | awk 'BEGIN{FS=","}{print $4}')
				blockageEnd=$(echo "$ablock" | sed 's/~LINEBREAK~/\n/g' | grep ",WAITING," -A 1 | tail -1 | awk 'BEGIN{FS=","}{print $1}')
				if [ -z "$blockageEnd" ]; then
					blockageEnd="$blockageStart"
				fi
				blockDuration=$(($blockageEnd-$blockageStart))
				#echo "DEBUG:$threadID:$blockageStart:$blockageEnd" >&2
				#exit 1
				waitingOn=$(cat "stacks/stack-$fileStamp.out" | grep "^\"$threadID\"" -A 3 | tail -1 | grep "waiting on")
				waitingToLock=$(cat "stacks/stack-$fileStamp.out" | grep "^\"$threadID\"" -A 3 | tail -1 | grep "waiting to lock")
				parkingToWaitFor=$(cat "stacks/stack-$fileStamp.out" | grep "^\"$threadID\"" -A 3 | tail -1 | grep "parking to wait for")
				if [ -n "$waitingOn" ]; then
					waitingOnId=$(echo "$waitingOn" | grep -o "[0-9]x[0-9a-f]*")
					resourceLockedBy=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingOnId>" -B 1 | head -1 |awk '{print $2}')
					desiredResource=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingOnId>"|sed 's/.*(/(/' | head -1)
				elif [ -n "$waitingToLock" ]; then
					waitingToLockId=$(echo "$waitingToLock" | grep -o "[0-9]x[0-9a-f]*")
					resourceLockedBy=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingToLockId>" -B 1|head -1|awk '{print $2}')
					desiredResource=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingToLockId>"|sed 's/.*(/(/' | head -1)
				elif [ -n "$parkingToWaitFor" ]; then
					parkingToWaitForId=$(echo "$parkingToWaitFor" | grep -o "[0-9]x[0-9a-f]*")
					resourceLockedBy=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$parkingToWaitForId>" -B 1|head -1|awk '{print $2}')
					if [ -z "$resourceLockedBy" ]; then
						resourceLockedBy=$(echo "$parkingToWaitFor" | sed -e 's/.*(//' -e 's/)$//')
					fi
				else
					waitingOnId=""
					resourceLockedBy=""
				fi
				
				echo "$blockageStart,$blockageEnd,$blockDuration,$threadID,$blockedTask,$resourceLockedBy,$desiredResource" >> .tmp/waits.out
				((i++))
			done
		done
	done

	if [ -f ".tmp/waits.out" ]; then
		cat .tmp/waits.out | awk 'BEGIN{FS=","}{print $5}' | sort | uniq -c | sort -n | tac > .tmp/top.waits.procs
		cat .tmp/waits.out | awk 'BEGIN{FS=","}{print $6}' | sort | sed 's/^$/Unexplained Mystery/' | uniq -c | sort -n | tac > .tmp/top.waits.cause
#		i=0; cat .tmp/waits.out | awk 'BEGIN{FS=","}{print $4 " " $1}' | sort | while read aline; do if [ "$lastID" != "$(echo "$aline" | awk '{print $1}')" -a "$i" -gt "0" ]; then echo "$lastID $ID_START_TIME $ID_LAST_TIME $(($ID_LAST_TIME-$ID_START_TIME))"; ID_START_TIME=$(echo "$aline" | awk '{print $2}'); elif [ "$i" == "0" ]; then ID_START_TIME=$(echo "$aline" | awk '{print $2}'); fi; ((i++)); ID_LAST_TIME=$(echo "$aline" | awk '{print $2}'); lastID="$(echo "$aline" | awk '{print $1}')"; if [ "$i" == "20" ]; then echo "$lastID $ID_START_TIME $ID_LAST_TIME $(($ID_LAST_TIME-$ID_START_TIME))"; fi; done | sort -n -k4 | while read athread; do
#			threadName=$(echo "$athread" | awk '{print $1}')
#			blockDuration=$(echo "$athread" | awk '{print $4}')
#			blockStart=$(date -d @$(echo "$athread" | awk '{print $2}') +"%D %T")
#			blockEnd=$(date -d @$(echo "$athread" | awk '{print $3}') +"%D %T")
#			echo "Thread: $threadName was waiting for $blockDuration secconds, from: $blockStart to: $blockEnd"
#		done | tac | head -n 25 | nl > .tmp/top.waits.duration

		cat .tmp/waits.out | sort -k3,3 -t, -n | tail -25 | tac | while read aline; do
			startTime=$(date -d @$(echo "$aline" | awk 'BEGIN{FS=","}{print $1}') +"%Y-%m-%d %T")
			endTime=$(date -d @$(echo "$aline" | awk 'BEGIN{FS=","}{print $2}') +"%Y-%m-%d %T")
			stringStart=$(echo "$aline" | awk 'BEGIN{FS=","}{print "Thread: "$4" was waiting for "$3" secconds, from:"}')
			echo "$stringStart $startTime to: $endTime"
		done | nl  > .tmp/top.waits.duration

		cat .tmp/waits.out | awk 'BEGIN{FS=","}{print $5}' | sort | uniq -c | sort -n | tac | sed 's/.*[0-9] //' | while read aline; do
			echo "    Wait: $aline, was caused by: "
			cat .tmp/waits.out | grep "$aline" | awk 'BEGIN{FS=","}{print $6 " locking the resource \"" $7 "\""}'|sed 's/^ locking the/_Unknown_ locking the/g'|sort|uniq -c|sort -n|tac
			echo ""
		done > .tmp/top.waits.details
	fi
}

function findLongRunning(){
	if [ -f ".tmp/proa1.out" ]; then
		rm .tmp/proa1.out
	fi

	#Process uniq thread tasks ignore state...
	cat .tmp/states.out | egrep "$CUSTOM_EX_PREP" | grep -vE "(sun.misc.Unsafe.park|AJP_WAITING)" | awk 'BEGIN{FS=","}{print $3 "," $4}' | sort -u | while read uniqTask; do
		threadIDP=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $1}')
		threadID=$(echo "$threadIDP" | sed -e 's/\[/\\[/' -e 's/\]/\\]/')
		threadProcess=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $2}')
		threadStart=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | head -1 | sed 's/,.*//')
		((threadStart--))
		threadEnd=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | tail -1 | sed 's/,.*//')
		echo "$(echo "$threadEnd-$threadStart" | bc),$threadIDP,$threadProcess,$(date -d @"$threadStart" +"%Y-%m-%d %T"),$(date -d @"$threadEnd" +"%Y-%m-%d %T")"
	done | sort -n | tail -30 | tac | tee -a .tmp/proa1.out

#	#Process longest thread proc running...
#	cat .tmp/states.out | grep "RUNNING" | awk 'BEGIN{FS=","}{print $3 "," $4}' | sort -u | while read uniqTask; do
#		threadIDP=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $1}')
#		threadID=$(echo "$threadIDP" | sed -e 's/\[/\\[/' -e 's/\]/\\]/')
#		threadProcess=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $2}')
#		threadStart=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | head -1 | sed 's/,.*//')
#		((threadStart--))
#		threadEnd=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | tail -1 | sed 's/,.*//')
#		echo "$(echo "$threadEnd-$threadStart" | bc),$threadIDP,$threadProcess,$(date -d @"$threadStart" +"%Y-%m-%d %T"),$(date -d @"$threadEnd" +"%Y-%m-%d %T")"
#	done | sort -n | tail -10 | tac | tee -a .tmp/proa3.out
#
#	#Process longest proc running...
#	cat .tmp/states.out | grep "WAITING" | awk 'BEGIN{FS=","}{print $3 "," $4}' | sort -u | while read uniqTask; do
#		threadIDP=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $1}')
#		threadID=$(echo "$threadIDP" | sed -e 's/\[/\\[/' -e 's/\]/\\]/')
#		threadProcess=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $2}')
#		threadStart=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | head -1 | sed 's/,.*//')
#		((threadStart--))
#		threadEnd=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | tail -1 | sed 's/,.*//')
#		echo "$(echo "$threadEnd-$threadStart" | bc),$threadIDP,$threadProcess,$(date -d @"$threadStart" +"%Y-%m-%d %T"),$(date -d @"$threadEnd" +"%Y-%m-%d %T")"
#	done | sort -n | tail -10 | tac | tee -a .tmp/proa5.out
#
#	#Process procs...
#	cat .tmp/states.out | grep "WAITING" | awk 'BEGIN{FS=","}{print $3 "," $4}' | sort -u | while read uniqTask; do
#		threadIDP=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $1}')
#		threadID=$(echo "$threadIDP" | sed -e 's/\[/\\[/' -e 's/\]/\\]/')
#		threadProcess=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $2}')
#		threadStart=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | head -1 | sed 's/,.*//')
#		((threadStart--))
#		threadEnd=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | tail -1 | sed 's/,.*//')
#		echo "$(echo "$threadEnd-$threadStart" | bc),$threadIDP,$threadProcess,$(date -d @"$threadStart" +"%Y-%m-%d %T"),$(date -d @"$threadEnd" +"%Y-%m-%d %T")"
#	done | sort -n | tail -10 | tac | tee -a .tmp/proa6.out
}

function graphables(){
	echo "summaryTime,SPARE,RUNNABLE,TIMEDWAITING,WAITING,BLOCKED,$(echo "$CUSTOM_EX_PREP" | sed -e 's/|/_/g' -e 's/[^a-zA-Z0-9_]//g'),MAXTHREADS" > .tmp/thread-summaries.csv

	#produce csv's for csv2rrd
	cat .tmp/states.out | awk 'BEGIN{FS=","}{print $1}' | sort -u | sort -n | while read summaryTime; do
		#echo "debug: summaryTime: $summaryTime"
		summaryCounts="$(cat .tmp/states.out | grep "^$summaryTime," | awk 'BEGIN{FS=","}{print $2}' | sort | uniq -c | sort -n)"
		RUNNABLE=$(echo "$summaryCounts" | grep " RUNNABLE$" | awk '{print $1}')
		if [ -z "$RUNNABLE" ]; then
			RUNNABLE="0"
		fi
		SPARE_WAITING=$(echo "$summaryCounts" | grep " SPARE_WAITING$" | awk '{print $1}')
		if [ -z "$SPARE_WAITING" ]; then
			SPARE_WAITING="0"
		fi
		TIMED_WAITING=$(echo "$summaryCounts" | grep " TIMED_WAITING$" | awk '{print $1}')
		if [ -z "$TIMED_WAITING" ]; then
			TIMED_WAITING="0"
		fi
		WAITING=$(echo "$summaryCounts" | grep " WAITING$" | awk '{print $1}')
		if [ -z "$WAITING" ]; then
			WAITING="0"
		fi
		BLOCKED=$(echo "$summaryCounts" | grep " BLOCKED$" | awk '{print $1}')
		if [ -z "$BLOCKED" ]; then
			BLOCKED="0"
		fi
		CUSTOM="$(cat .tmp/states.out | grep "^$summaryTime," | egrep ",$CUSTOM_EX_PREP" | wc -l)"
		echo "$summaryTime,$SPARE_WAITING,$RUNNABLE,$TIMED_WAITING,$WAITING,$BLOCKED,$CUSTOM,$MAX_THREADS" >> .tmp/thread-summaries.csv
		#echo "DEBUG2: $summaryTime,$RUNNABLE,$TIMED_WAITING,$WAITING,$BLOCKED"
	done
	#duplicate
	START_TIME=$(head -2 .tmp/thread-summaries.csv | tail -1 | awk 'BEGIN{FS=","}{print $1}')
	lastDaten1="$START_TIME"
	echo "summaryTime,SPARE,RUNNABLE,TIMEDWAITING,WAITING,BLOCKED,$(echo "$CUSTOM_EX_PREP" | sed -e 's/|/_/g' -e 's/[^a-zA-Z0-9_]//g'),MAXTHREADS" > .tmp/thread-summaries.dup.csv
	cat .tmp/thread-summaries.csv | tail -n +2 | sort -un | while read aline; do
		myTime=$(echo "$aline" | awk 'BEGIN{FS=","}{print $1}')
		while [ "$lastDaten1" -lt "$myTime" ]; do
			if [ -n "$lastData" ]; then
				echo "$lastDaten1,$lastData" >> .tmp/thread-summaries.dup.csv
			else
				echo "skipping..."
			fi
			((lastDaten1++))
		done
		lastData=$(echo "$aline" | awk 'BEGIN{FS=","}{print $2 "," $3 "," $4 "," $5 "," $6 "," $7 "," $8 }')
		echo "$aline" >> .tmp/thread-summaries.dup.csv
		lastDaten1="$(($myTime+1))"
	done
	#source cvs2rrd
	source ../csv2rrd/csv2rrd
	#convert cvs2rrd
	if [ -f ".tmp/thread-summaries.dup.rrd" ]; then
		rm -rvf ".tmp/thread-summaries.dup.rrd"
	fi
	csv2rrd .tmp/thread-summaries.dup.csv .tmp/thread-summaries.dup.rrd
	#graph cvs2rrd
	if [ -f ".tmp/cool.png" ]; then
		rm .tmp/cool.png
	fi
	buildGraph .tmp/thread-summaries.dup.rrd .tmp/cool.png "Thread Status"
}

function printReport(){

	# BLOCKAGES...

	if [ -f ".tmp/top.blocked.procs" ]; then
		echo "----------------------------------------"
		echo "Top blocked process..."
		echo ""
		cat .tmp/top.blocked.procs
		echo ""
	fi
	if [ -f ".tmp/top.block.cause" ]; then
		echo "Top occuring blockages causes..."
		echo ""
		cat .tmp/top.block.cause
		echo ""
	fi
	if [ -a ".tmp/top.blocks.duration" ]; then
		echo "Longest blocked processes..."
		echo ""
		cat .tmp/top.blocks.duration
		echo ""
	fi
	if [ -f ".tmp/top.blocks.details" ]; then
		echo "----------------------------------------"
		echo "Blockage details..."
		echo "----------------------------------------"
		echo ""
		cat .tmp/top.blocks.details
		echo ""
	fi

	# WAITS...

	if [ -f ".tmp/top.waits.procs" ]; then
		echo "----------------------------------------"
		echo "Top waiting process..."
		echo ""
		cat .tmp/top.waits.procs
		echo ""
	fi
	if [ -f ".tmp/top.waits.cause" ]; then
		echo "Top occuring wait causes..."
		echo ""
		cat .tmp/top.waits.cause
		echo ""
	fi
	if [ -a ".tmp/top.waits.duration" ]; then
		echo "Longest waiting processes..."
		echo ""
		cat .tmp/top.waits.duration
		echo ""
	fi
	if [ -f ".tmp/top.waits.details" ]; then
		echo "----------------------------------------"
		echo "Long Wait details..."
		echo "----------------------------------------"
		echo ""
		cat .tmp/top.waits.details
		echo ""
	fi

	# Performance...
	if [ -f ".tmp/proa1.out" ]; then
		#Process uniq thread tasks ignore state...
		echo "----------------------------------------"
		echo "Longest time process..."
		echo "----------------------------------------"
		cat .tmp/proa1.out
	fi

	if [ -f ".tmp/proa3.out" ]; then
		#Process longest thread proc running...
		echo "----------------------------------------"
		echo "Longest thread runnning persistantly in running state only..."
		echo "----------------------------------------"
		cat .tmp/proa3.out
	fi

	if [ -f ".tmp/proa5.out" ]; then
		#Process longest proc running...
		echo "----------------------------------------"
		echo "SUM: longest procs running..."
		echo "----------------------------------------"
		cat .tmp/proa5.out
	fi

	if [ -f ".tmp/proa6.out" ]; then
		#Process procs...
		echo "----------------------------------------"	
		echo "SUM: longest procs..."
		echo "----------------------------------------"
		cat .tmp/proa6.out
	fi

	#Process thread types...

	#Thread counts...
	if [ -f ".tmp/maxed.out" ]; then
		echo "----------------------------------------"	
		echo "MAXED OUT: high thread count stacks..."
		echo "----------------------------------------"
		cat .tmp/maxed.out
	fi
	
}

normalizeStacks
maxedOutThreads
findBlockages
findWait
findLongRunning
graphables

printReport | tee -a "reports/Report-$(date +"%Y%m%d-%H%M%S").txt"

