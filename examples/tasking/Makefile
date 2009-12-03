# Avoid executing this test if tasking is not supported (ZFP run time)

IS_ZFP_DIR:=$(shell $(PREFIX)gnatls $(RUNTIME) -v | fgrep adalib | fgrep rts-zfp)

ifeq ($(IS_ZFP_DIR),)
TARGET=test
else
TARGET=unsupported
endif

all: $(TARGET)

test:
	$(PREFIX)gnatmake $(RUNTIME) -P prj;
	gnat stack -P prj;

unsupported:
	echo "Tasking not supported with this run time"

clean:
	$(PREFIX)gnatclean -P prj
	rm -f *.ci undefined.ciu graph.vcg
