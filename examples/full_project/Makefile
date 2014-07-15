ifeq ($(TARGET),)
TOOL_TARGET=
else
TOOL_TARGET=--target=$(TARGET)
endif

all:
	gprbuild $(TOOL_TARGET) $(RUNTIME) -P prj
	gnatstack $(TOOL_TARGET) $(RUNTIME) -P prj

clean:
	$(PREFIX)gnatclean -r -P prj
	rm -f *.ci prj1/*.ci undefined.ciu graph.vcg

.PHONY: clean main_unit
