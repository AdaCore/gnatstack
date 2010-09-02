#!/bin/bash

# Default target

TARGET=leon-elf

# Set cross tools if needed

if [ "$TARGET" = "" ]; then
   GNATMAKE=gnatmake
   GNATCHOP=gnatchop
   GNATCLEAN=gnatclean
else
   GNATMAKE="$TARGET-gnatmake"
   GNATCHOP="$TARGET-gnatchop"
   GNATCLEAN="$TARGET-gnatclean"
fi;

# Sometimes it it not possible to modify all the data in the part of the
# stack that is being used. Therefore, we add an expected margin between
# the amount of stack actually modified and the stack allocation.

case $TARGET in
    # On SPARC-based targets, the last frame which is called reserves
    # at least 96 bytes. The minimum stack frame contains 16-word window
    # save area, plus struct/union return pointer, plus 6 outgoing
    # parameters. These are only 92 bytes but the stack and frame pointer 
    # require to be on a eight byte boundary, hence the minimum stack frame
    # size is 96 bytes.
    erc32-elf|leon-elf|leon3-elf) expected_margin=96;;
    *)                            expected_margin=0;;
esac

testsuite_dir=`pwd`

files=`cd tests; echo *.ada`

rm -rf obj;
mkdir obj;
cd obj;

# Iterate over all test cases

for file in $files; do
    name=${file%\.*}

    echo "========================================================";
    echo "Test $name";

    # Create directory for each individual test

    rm -rf $name;
    mkdir $name;
    cd $name;

    # Build

    # Extra flags for building the application

    case $TARGET in
	erc32-elf|leon-elf|leon3-elf)
	    # SPARC-based compilers share some code
	    EXTRA_FLAGS="-I$testsuite_dir/support/target-support/sparc-elf";;
	*)
	    EXTRA_FLAGS="";;
    esac

    # Extract source code
   
    $GNATCHOP -w -c -q ../../tests/$file;

    # Extract other files associated to the test, if they exist

    if [ -s ../../tests/$name.tgz ]; then
	tar xzf ../../tests/$name.tgz
    fi;

    $GNATMAKE -O1 -gnatn -fcallgraph-info=su,da --RTS=zfp \
       -I$testsuite_dir/support \
       -I$testsuite_dir/support/target-support/$TARGET \
       $EXTRA_FLAGS test > $name.build 2>&1

    # Execute

    if [ -x test ]; then
	case $TARGET in
	    erc32-elf|leon-elf|leon3-elf) echo "go" > tsim_commands;
	                                  echo "quit" >> tsim_commands;
                                          ARGS="-c tsim_commands";;
	    *)                            ARGS="";;
        esac

	case $TARGET in
	    erc32-elf) RUN=tsim-erc32;;
	    leon-elf)  RUN=tsim-leon;;
	    leon3-elf) RUN=tsim-leon3;;
            *)         RUN=""
	esac

	$RUN ./test $ARGS > $name.output;
    else
	echo "Could not find executable for test $name"
    fi;

    # Get maximum stack usage

    grep "Stack usage: " $name.output | sed 's/[^0-9]//g;s/^[0]*//' | \
       tr -d '\n' > actual_stack_usage

    # Get GNATstack information

    gnatstack -q *.ci > $name.gnatstack_result

    # Get worst-case stack requirements from GNATstack

    grep ": total" $name.gnatstack_result | sed 's/[^0-9]//g' | \
       tr -d '\n' > max_stack_usage
    
    # $GNATCLEAN -q test;

    # Print outline of stack information

    if [ -s actual_stack_usage ]; then
        actual=`cat actual_stack_usage`
	echo "Stack used: $actual bytes"
    else
	actual=0
        echo "Unknown stack usage"
    fi;

    if [ -s max_stack_usage ]; then
        max=`cat max_stack_usage`
	echo "GNATstack maximum stack usage: $max bytes"
    else
	max=0
        echo "Unknown stack requirements"
    fi;

    # Verify whether actual stack usage and worst-case requirements provided
    # by GNATstack are coherent.

    if [ $actual -gt 0 -a $max -gt 0 ]; then
        dif=$(($max-$actual))
	echo "Difference: $dif bytes"

        if [ $dif -lt 0 ]; then
	    echo "Test error: GNATstack did not compute a big enough worst case"
	elif [ $dif -gt $expected_margin ]; then
	    echo "Test error: GNATstack did not compute a tight worst case"
        else
	    echo "Test OK"
        fi;
    else
	echo "Test error: not enough information"
    fi;

    # Check whether there is any unexpected warning in the stack output
    # of GNATstack. This is indicated by an stack usage of "total X+? bytes"

    if [ "`egrep 'total [0-9]+\+\? bytes' $name.gnatstack_result`" != "" ]; then
       echo "WARNING: GNATstack indicated computation not accurate"
    fi;

    echo "========================================================";
    
    cd ..;
done;

cd ..;
