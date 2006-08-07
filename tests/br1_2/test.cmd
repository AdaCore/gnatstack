rm -f c_test *.ci *.vcg *.ciu
gcc -fcallgraph-info=su -o c_test c_test.c
gnatstack -a c_test.ci
