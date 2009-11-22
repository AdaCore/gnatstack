all:
	$(CC) -fcallgraph-info=su main.cpp
	gnatstack -p *.ci

clean:
	rm -f *.o *.ci a.out undefined.ciu graph.vcg
