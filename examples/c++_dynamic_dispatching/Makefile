all:
	$(CC) -fcallgraph-info=su -c data_handling.cpp
	$(CC) -fcallgraph-info=su main.cpp data_handling.o
	gnatstack -Wa -p *.ci

clean:
	rm -f *.o *.ci a.out undefined.ciu graph.vcg
