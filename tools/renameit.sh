#!/bin/bash

find ../stacks/ -type f ! -iname "readme.txt" ! -iname "stack-*" | while read af; do
	checkDate=$(cat "$af" | grep "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]" | head -1)
	if [ -n "$checkDate" ]; then
		newDate=$(date -d "$checkDate" +"%s")
		mv "$af" "../stacks/stack-$newDate.out"
	fi
done
