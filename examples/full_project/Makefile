all:
	$(PREFIX)gnatmake $(RUNTIME) -P prj
	$(PREFIX)gnat stack -P prj -U

clean:
	$(PREFIX)gnatclean -r -P prj
	rm -f *.ci prj1/*.ci undefined.ciu graph.vcg

.PHONY: clean main_unit
