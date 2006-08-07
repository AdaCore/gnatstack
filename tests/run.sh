#!/bin/sh

diff="diff -u"
tests=${@:-*}
testpwd=`pwd`

export PATH=$testpwd/..:$PATH

export diff gnatstack

# Run each test

for dir in $tests; do
   cd $testpwd

   if [ -d $dir ]; then
      cd $dir

      if [ -f test.cmd ]; then
         out=out.$$

         sh test.cmd > $out 2>&1
         run_status=$?

         cmp $out test.out > /dev/null 2>&1
         cmp_status=$?

         if [ "$run_status" = "0" -a "$cmp_status" = "0" ]; then
            echo "PASSED $dir"
         else
            echo "FAILED $dir"
         fi

         rm $out
      else
         echo "=== no test.cmd in $dir"
      fi
   fi
done

