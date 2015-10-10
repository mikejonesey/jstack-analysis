# Intro
This project is for analysing java stack traces, the project is usefull for quickly getting an overview of a jvm's state, or as a tool for analysing states over a long time. The tool currenly identifies core issues to performance, further analysis of the identified issues is then required.

# Instructions for running:
1. [checkout this project](wiki/checkout-this-project.md)
2. [generate some stack traces](wiki/generate-stack-traces.md) and place them into the ./stacks dir.
3. run the ./stack-analysis.sh script

# Structure
The project is self contained with no dependancies other than common bash utilities. If you want graphs from rrdtool then you'll need to also checkout the csv2rrd repo.
The repositories should be checked out into the same working directory, exaple:
/home/mike/workingdir/stack-analysis
and
/home/mike/workingdir/csv2rrd

## Directories:
 - ./.tmp - this directory contains temp data when stacks are tested, rrdtool will also be used to produce a png graph in this dir.
 - ./reports - after each run of the stack analysis a report will be generated in this dir with a unique name.
 - ./src - unused
 - ./stacks - this is where you can place stacks for analysis.
 - ./tools - handy bash scripts.

## Files:
 - ./.gitignore - preventing data from being checked in
 - ./stack-analysis.sh - the main script.

# Notes:
- if you use a mac checkout the macosx branch as there are a few changes between the tools used.
