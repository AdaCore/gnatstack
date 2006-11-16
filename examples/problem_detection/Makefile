all:
	$(PREFIX)gcc -c -gnatp $(RUNTIME) ext.adb
	$(PREFIX)gnatmake -gnatp -gnat05 $(RUNTIME) p -cargs -fcallgraph-info=su
	$(PREFIX)gnatstack -p -Wa -v *.ci

clean:
	rm -f *.o *.ali b~* *.ci p$(EXE) undefined.ciu graph.vcg
