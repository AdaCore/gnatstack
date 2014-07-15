ifeq ($(TARGET),)
GNATSTACK_TARGET=
else
GNATSTACK_TARGET=--target=$(TARGET)
endif

all:
	-$(PREFIX)gnatmake $(RUNTIME) -P prj
	gnatstack $(GNATSTACK_TARGET) $(RUNTIME) -P prj

clean:
	$(PREFIX)gnatclean -P prj
	rm -f *.ci undefined.ciu graph.vcg
