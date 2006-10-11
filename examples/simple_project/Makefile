all:
	$(PREFIX)gnatmake -P prj
	gnat stack -P prj

clean:
	$(PREFIX)gnatclean -P prj
	rm -f *.ci undefined.ciu graph.vcg
