all:
	-$(PREFIX)gnatmake $(RUNTIME) main_unit -cargs -fcallgraph-info=su
	gnatstack -p *.ci

clean:
	rm -f *.o *.ali b~* *.ci main_unit$(EXE) undefined.ciu graph.vcg
