# Generating Stack Traces
The best tool for generating stacks quickly is jstack, which comes with the jdk (not the jre).

# Generate stacks using jstack
1. switch user to the same user running the java process to be tested
2. use jstack -l [PID] > stack-[date].out

For checking the machine state after an error, take 1-10 dumps, for performance monitoring you will need to take dumps for a long duration. Dependant on the test time, the time between dumps will need tweeking between 0-10 secconds.

example dump generation:
> su java-user  
> cd /tmp  
> mkdir stacks1  
> cd stacks1  
> for ((i=0; i&lt;10; i++)); do jstack -l [pid] > stack-$(date +"%s").out; done  

If you don't have access to a jdk, you can use kill -3 [pid], to have java print a stacktrace to log.

Place all stack traces for analysis in the ~/workingdir/stack-analysis/stacks/ directory.

stack trace files should be named in the format stack-TIMESTAMP.out
