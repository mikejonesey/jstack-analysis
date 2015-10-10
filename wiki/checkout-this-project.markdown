# Checking out this project
1. Create a working directory for your stack trace analysis; you can call this directory anything you like:

> mkdir ~/stack-check

2. Checkout the project:

> cd ~/stack-check
> git clone https://gitlab.mikejonesey.co.uk/java/stack-analysis.git

3. If you don't want to setup rrdtool, comment out the "graphables" function call near the bottom of stack-analysis.sh

> normalizeStacks  
> maxedOutThreads  
> findBlockages  
> findWait  
> findLongRunning  
> #graphables 

4. If you do want rrdtool graphs, checkout the csv2rrd project into the same working directory.

> cd ~/stack-check
> git clone https://gitlab.mikejonesey.co.uk/linux-tools/csv2rrd.git

# Mac users
If you are using a mac, some of the unix tools vary, checkout the macosx branch for support with the default mac toolset.
> cd ~/stack-check
> git checkout macosx -f