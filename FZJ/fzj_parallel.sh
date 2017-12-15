#!/bin/bash

#
# This is a modified version of a script published by kawakamasu on May 22, 2008
# http://pebblesinthesand.wordpress.com/category/parallel-computing/
#


MY_PID=$$

function childPIDs () {
    CURRENT_PID=$1
    if [[ -n $CURRENT_PID ]]; then
        local CHILDREN_PIDS=$( ps -o pid= --ppid $CURRENT_PID )
        ALL_PIDS="$ALL_PIDS $( echo -ne $CHILDREN_PIDS )"
        for i in $CHILDREN_PIDS; do
            childPIDs $i
        done
    fi
    #echo $ALL_PIDS
}

control_c() {
    echo "Control-C"
    echo "  - terminating all child processes"

    # empty queue to prevent new jobs getting started
    QUEUE=""

    # get the PIDs of all child processes
    ALL_PIDS="" #$MY_PID
    childPIDs $MY_PID

    EXE="kill -2 $ALL_PIDS"  # -2 sends SIGINT (=ctrl-c)
    echo $EXE
    eval "$EXE"

    sleep 1

    EXE="kill $ALL_PIDS"
    echo $EXE
    eval "$EXE"

    sleep 1
    echo "  - exiting"
    exit 130
}

trap control_c SIGINT


# function to compute the number of threads to 
# achieve 100% load
function dynamic_threads() {
    CURRENT_LOAD=$(ps -eo pcpu | awk {'sum+=$1;print sum/100'} | tail -n 1)
    THREADS=$(printf "%0.0f" $(echo "$NUM_CPU - $CURRENT_LOAD" | bc -l))
    if [[ $THREADS -lt 1 ]]; then
        THREADS=1
    fi
    echo $THREADS
}


# set default values
NUM=0
QUEUE=""
NUM_CPU=$(cat /proc/cpuinfo | grep -e '^processor' | wc -l)  # was: $(nproc)
MAX_NPROC=$NUM_CPU
if [[ -n $FZJ_NUM_PROCS ]]; then
    MAX_NPROC=$FZJ_NUM_PROCS
elif [[ -n $OMP_NUM_THREADS ]]; then
    MAX_NPROC=$OMP_NUM_THREADS
fi
REPLACE_CMD=0 # no replacement by default
JOB_FILE=""
USAGE="A simple wrapper for running processes in parallel.
Usage: $(basename $0) [-h] [-r] [-j nb_jobs] command arg_list
    -h           : Shows this help
    -m <file>    : Execute each line of the given file
    -j <nb_jobs> : Set number of simultaneous jobs, a positive integer, 'dynamic' for load specific number of threads or 'all' for all CPUs (default: $MAX_NPROC)
 Examples:
    $(basename $0) somecommand arg1 arg2 arg3
    $(basename $0) -j 3 \"somecommand -r -p\" arg1 arg2 arg3
    $(basename $0) -j 6 -r \"convert -scale 50% * small/small_*\" *.jpg
    $(basename $0) -m myjobs.txt"

function queue {
    QUEUE="$QUEUE $1"
    NUM=$(($NUM+1))
}

function regeneratequeue {
    OLDREQUEUE=$QUEUE
    QUEUE=""
    NUM=0
    for PID in $OLDREQUEUE
    do
        if [ -d /proc/$PID  ] ; then
            QUEUE="$QUEUE $PID"
            NUM=$(($NUM+1))
        fi
    done
}

function checkqueue {
    OLDCHQUEUE=$QUEUE
    for PID in $OLDCHQUEUE
    do
        if [ ! -d /proc/$PID ] ; then
            regeneratequeue # at least one PID has finished
            break
        fi
    done
}

# parse command line
if [ $# -eq 0 ]; then #  must be at least one arg
    echo "$USAGE" >&2
    exit 1
fi

while getopts j:hm: OPT; do # "j:" waits for an argument "h" doesn't
    case $OPT in
    h)  echo "$USAGE"
        exit 0 ;;
    j)  MAX_NPROC=$OPTARG ;;
    m)  JOB_FILE=$OPTARG ;;
    \?) # getopts issues an error message
        echo "$USAGE" >&2
        exit 1 ;;
    esac
done

# ensure that there is a job file
if [[ -z $JOB_FILE ]]; then
    echo "$USAGE" >&2
    echo
    echo "Error: no file with jobs"
    exit 1
fi

# if requested use all cpu cores
if [[ ${MAX_NPROC,,} == "all" ]]; then
    MAX_NPROC=$(cat /proc/cpuinfo | grep -e '^processor' | wc -l)  # was: $(nproc)
fi

# Main program
while read CMD; do
    #echo "Running $CMD"

    /bin/bash -c "$CMD" &

    PID=$!
    queue $PID

    if [[ ${MAX_NPROC,,} == 'dynamic' ]]; then
        while [ $NUM -ge $(dynamic_threads) ]; do
            checkqueue
            sleep 0.4
        done
    else
        while [ $NUM -ge $MAX_NPROC ]; do
            checkqueue
            sleep 0.4
        done
    fi
done < $JOB_FILE

wait # wait for all processes to finish before exit
