#!/bin/bash

cd stacks

ls | grep -v txt | while read af; do d1=$(date -d "$(head -1 $af)" +%s); mv "$af" "stack-$d1.out"; done
