# Avoid executing this test if tasking is not supported (ZFP run time)

IS_ZFP_DIR:=$(shell $(PREFIX)gnatls $(RUNTIME) -v | fgrep adalib | fgrep rts-zfp)

ifeq ($(IS_ZFP_DIR),)
EXEC=test
else
EXEC=unsupported
endif

ifeq ($(TARGET),)
GNATSTACK_TARGET=
else
GNATSTACK_TARGET=--target=$(TARGET)
endif

all: $(EXEC)

test:
	-gprbuild $(GNATSTACK_TARGET) $(RUNTIME) -P prj;
	gnatstack $(GNATSTACK_TARGET) $(RUNTIME) -P prj;

unsupported:
	echo "Tasking not supported with this run time"

clean:
	gprclean -P prj
	rm -f *.ci undefined.ciu graph.vcg
