ifeq ($(TARGET),)
GNATSTACK_TARGET=
else
GNATSTACK_TARGET=--target=$(TARGET)
endif

all:
	-$(PREFIX)gnatmake $(RUNTIME) main_unit -cargs -fcallgraph-info=su
	gnatstack $(GNATSTACK_TARGET) $(RUNTIME) -p *.ci

clean:
	rm -f *.o *.ali b~* *.ci main_unit$(EXE) undefined.ciu graph.vcg
