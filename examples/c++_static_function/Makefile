all:
	$(CC) -c -fcallgraph-info=su data_handling.cpp
	$(CC) -fcallgraph-info=su main.cpp data_handling.o
	gnatstack -p *.ci

clean:
	rm -f *.o *.ci a.out undefined.ciu graph.vcg
