#!/bin/bash

cd ../

find stacks/ -type f -iname "stack-*" | while read af; do
	touch -d "$(date -d @$(echo "$af" | grep -o "[0-9]*") +"%D %T")" $af
done
