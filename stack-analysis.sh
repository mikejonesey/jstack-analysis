#!/bin/bash

if [ -f ".tmp/blocks.out" ]; then
  rm -rvf .tmp/blocks.out
fi

#if [ 1 == 2 ]; then
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
		if [ -n "$procy" -a -n "$procyState" ]; then
			echo "$fileStamp,$procyState,$athread,$procy" >> .tmp/states.out
		fi
	done
done
#fi

function findBlockages(){
	cat .tmp/states.out | grep ,BLOCKED, | awk 'BEGIN{FS=","}{print $3}' | sort -u | while read bNode; do
		echo "Processing blockages in thread $bNode"
		cat .tmp/states.out | grep "$bNode" | sort -n | sed -e 's/,RUNNABLE,\(.*\)/,RUNNABLE,\1\n~ENDBLOCK~/g' | sed  -e ':amoo;N;$!bamoo;s/\n/~LINEBREAK~/g' -e 's/~ENDBLOCK~/\n/g' | sed 's/^~LINEBREAK~//' | while read ablock; do
			i=1
			#to process all blocks head must be removed and times augmented to thread level
			echo "$ablock" | sed 's/~LINEBREAK~/\n/g' | grep ",BLOCKED," | head -1 | while read aline; do
				fileStamp=$(echo "$aline" | awk 'BEGIN{FS=","}{print $1}')
				#echo "Processing blockage at $fileStamp in thread \"$bNode\""
				#echo "DEBUG:1001"
				threadID=$(echo "$aline" | awk 'BEGIN{FS=","}{print $3}')
				blockageStart=$(echo "$aline" | awk 'BEGIN{FS=","}{print $1}')
				blockedTask=$(echo "$aline" | sed 's/~LINEBREAK~/\n/g' | grep ",BLOCKED," -A 1 | head -1 | awk 'BEGIN{FS=","}{print $4}')
				blockageEnd=$(echo "$ablock" | sed 's/~LINEBREAK~/\n/g' | grep ",BLOCKED," -A 1 | tail -1 | awk 'BEGIN{FS=","}{print $1}')
				waitingOn=$(cat "stacks/stack-$fileStamp.out" | grep "^\"$threadID\"" -A 3 | tail -1 | grep "waiting on")
				waitingToLock=$(cat "stacks/stack-$fileStamp.out" | grep "^\"$threadID\"" -A 3 | tail -1 | grep "waiting to lock")
				if [ -n "$waitingOn" ]; then
					waitingOnId=$(echo "$waitingOn" | grep -o "[0-9]x[0-9a-f]*")
					resourceLockedBy=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingOnId>" -A 1 | tail -1 |awk '{print $2}')
					desiredResource=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingOnId>"|sed 's/.*(/(/')
				elif [ -n "$waitingToLock" ]; then
					waitingToLockId=$(echo "$waitingToLock" | grep -o "[0-9]x[0-9a-f]*")
					resourceLockedBy=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingToLockId>" -A 1|tail -1|awk '{print $2}')
					desiredResource=$(cat "stacks/stack-$fileStamp.out" | grep " locked <$waitingToLockId>"|sed 's/.*(/(/')
				else
					waitingOnId=""
					resourceLockedBy=""
				fi
				
				#echo "---"
				#echo "$ablock" | sed 's/~LINEBREAK~/\n/g' | nl
				#echo "---"
				#echo "$aline" | sed 's/~LINEBREAK~/\n/g' | nl
				#echo "---"
				#echo "$fileStamp,$threadID,$blockedTask,$resourceLockedBy,$desiredResource"
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
		done | tac | nl > .tmp/top.blocks.duration
		cat .tmp/blocks.out | awk 'BEGIN{FS=","}{print $3}' | sort | uniq -c | sort -n | tac | sed 's/.*[0-9] //' | while read aline; do
			echo "    Blockage: $aline, was caused by: "
			cat .tmp/blocks.out | grep "$aline" | awk 'BEGIN{FS=","}{print $4 " locking the resource \"" $5 "\""}'|sort|uniq -c|sort -n|tac
			echo ""
		done > .tmp/top.blocks.details
	fi
}

function findLongRunning(){
	cat .tmp/states.out | awk 'BEGIN{FS=","}{print $3 "," $4}' | sort -u | while read uniqTask; do
		threadIDP=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $1}')
		threadID=$(echo "$threadIDP" | sed -e 's/\[/\\[/' -e 's/\]/\\]/')
		threadProcess=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $2}')
		threadStart=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | head -1 | sed 's/,.*//')
		((threadStart--))
		threadEnd=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | tail -1 | sed 's/,.*//')
		echo "$(echo "$threadEnd-$threadStart" | bc),$threadIDP,$threadProcess,$(date -d @"$threadStart" +"%Y-%m-%d %T"),$(date -d @"$threadEnd" +"%Y-%m-%d %T")"
	done | sort -n | tail -30 | tac | tee -a .tmp/proa1.out

	cat .tmp/states.out | grep "WAITING" | awk 'BEGIN{FS=","}{print $3 "," $4}' | sort -u | while read uniqTask; do
		threadIDP=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $1}')
		threadID=$(echo "$threadIDP" | sed -e 's/\[/\\[/' -e 's/\]/\\]/')
		threadProcess=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $2}')
		threadStart=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | head -1 | sed 's/,.*//')
		((threadStart--))
		threadEnd=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | tail -1 | sed 's/,.*//')
		echo "$(echo "$threadEnd-$threadStart" | bc),$threadIDP,$threadProcess,$(date -d @"$threadStart" +"%Y-%m-%d %T"),$(date -d @"$threadEnd" +"%Y-%m-%d %T")"
	done | sort -n | tail -10 | tac | tee -a .tmp/proa2.out

	cat .tmp/states.out | grep "RUNNING" | awk 'BEGIN{FS=","}{print $3 "," $4}' | sort -u | while read uniqTask; do
		threadIDP=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $1}')
		threadID=$(echo "$threadIDP" | sed -e 's/\[/\\[/' -e 's/\]/\\]/')
		threadProcess=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $2}')
		threadStart=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | head -1 | sed 's/,.*//')
		((threadStart--))
		threadEnd=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | tail -1 | sed 's/,.*//')
		echo "$(echo "$threadEnd-$threadStart" | bc),$threadIDP,$threadProcess,$(date -d @"$threadStart" +"%Y-%m-%d %T"),$(date -d @"$threadEnd" +"%Y-%m-%d %T")"
	done | sort -n | tail -10 | tac | tee -a .tmp/proa3.out

	cat .tmp/states.out | grep "WAITING" | awk 'BEGIN{FS=","}{print $3 "," $4}' | sort -u | while read uniqTask; do
		threadIDP=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $1}')
		threadID=$(echo "$threadIDP" | sed -e 's/\[/\\[/' -e 's/\]/\\]/')
		threadProcess=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $2}')
		threadStart=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | head -1 | sed 's/,.*//')
		((threadStart--))
		threadEnd=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | tail -1 | sed 's/,.*//')
		echo "$(echo "$threadEnd-$threadStart" | bc),$threadIDP,$threadProcess,$(date -d @"$threadStart" +"%Y-%m-%d %T"),$(date -d @"$threadEnd" +"%Y-%m-%d %T")"
	done | sort -n | tail -10 | tac | tee -a .tmp/proa4.out

	cat .tmp/states.out | grep "WAITING" | awk 'BEGIN{FS=","}{print $3 "," $4}' | sort -u | while read uniqTask; do
		threadIDP=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $1}')
		threadID=$(echo "$threadIDP" | sed -e 's/\[/\\[/' -e 's/\]/\\]/')
		threadProcess=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $2}')
		threadStart=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | head -1 | sed 's/,.*//')
		((threadStart--))
		threadEnd=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | tail -1 | sed 's/,.*//')
		echo "$(echo "$threadEnd-$threadStart" | bc),$threadIDP,$threadProcess,$(date -d @"$threadStart" +"%Y-%m-%d %T"),$(date -d @"$threadEnd" +"%Y-%m-%d %T")"
	done | sort -n | tail -10 | tac | tee -a .tmp/proa5.out

	cat .tmp/states.out | grep "WAITING" | awk 'BEGIN{FS=","}{print $3 "," $4}' | sort -u | while read uniqTask; do
		threadIDP=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $1}')
		threadID=$(echo "$threadIDP" | sed -e 's/\[/\\[/' -e 's/\]/\\]/')
		threadProcess=$(echo "$uniqTask" | awk 'BEGIN{FS=","}{print $2}')
		threadStart=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | head -1 | sed 's/,.*//')
		((threadStart--))
		threadEnd=$(cat .tmp/states.out |grep "$uniqTask" | sort -n | tail -1 | sed 's/,.*//')
		echo "$(echo "$threadEnd-$threadStart" | bc),$threadIDP,$threadProcess,$(date -d @"$threadStart" +"%Y-%m-%d %T"),$(date -d @"$threadEnd" +"%Y-%m-%d %T")"
	done | sort -n | tail -10 | tac | tee -a .tmp/proa6.out
}

function printReport(){
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

	if [ -f ".tmp/proa1.out" ]; then
		#Process uniq thread tasks ignore state...
		echo "----------------------------------------"
		echo "Longest time process..."
		echo "----------------------------------------"
		cat .tmp/proa1.out
	fi

	if [ -f ".tmp/proa2.out" ]; then
		#Process longest thread proc waiting...
		echo "----------------------------------------"
		echo "Longest thread stuck in waiting..."
		echo "----------------------------------------"
		cat .tmp/proa2.out
	fi

	if [ -f ".tmp/proa3.out" ]; then
		#Process longest thread proc running...
		echo "----------------------------------------"
		echo "Longest thread runnning persistantly in running state only..."
		echo "----------------------------------------"
		cat .tmp/proa3.out
	fi

	if [ -f ".tmp/proa4.out" ]; then
		#Process longest proc waiting...
		echo "----------------------------------------"
		echo "SUM: longest procs waiting..."
		echo "----------------------------------------"
		cat .tmp/proa4.out
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
}

findBlockages
#findLongRunning

printReport | tee -a "reports/Report-$(date +"%Y%m%d-%H%M%S").txt"

