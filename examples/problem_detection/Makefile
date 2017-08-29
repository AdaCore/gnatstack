ifeq ($(TARGET),)
TOOL_TARGET=
else
TOOL_TARGET=--target=$(TARGET)
endif

all:
	-gprbuild $(TOOL_TARGET) $(RUNTIME) -P prj
	gnatstack $(TOOL_TARGET) $(RUNTIME) -P prj

clean:
	gprclean -P prj
	rm -f *.ci undefined.ciu graph.vcg
