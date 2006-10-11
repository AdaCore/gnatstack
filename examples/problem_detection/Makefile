all:
	$(PREFIX)gnatmake p -cargs -fcallgraph-info=su
	gnatstack -p -Wa -v *.ci

clean:
	rm -f *.o *.ali b~* *.ci p$(EXE) undefined.ciu graph.vcg
