all:
	$(PREFIX)gnatmake $(RUNTIME) -P prj
	$(PREFIX)gnat stack -P prj

clean:
	$(PREFIX)gnatclean -P prj
	rm -f *.ci undefined.ciu graph.vcg
