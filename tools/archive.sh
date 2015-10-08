#!/bin/bash

cd ../

read -p "Archive Name: " archName

newArchive=$(echo "$archName" | sed -e 's/ /_/g' -e 's/[^a-zA-Z0-9_-]//g')"_"$(date +"%s")

mkdir -p archive/$newArchive

find stacks -type f -iname "stack-*.out" -exec mv '{}' archive/$newArchive/ \;
mv .tmp/cool.png archive/$newArchive/states.png
mv reports/$(ls -rt reports | tail -1) archive/$newArchive/

