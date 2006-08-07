rm -f b~* *.o *.ali ada_test *.ci *.vcg *.ciu
gnatmake -q -fcallgraph-info=su -gnat05 ada_test.adb
gnatstack -a ada_test.ci
