all: dtbTool dtbSplit

dtbTool: dtbTool.c
	$(CC) -static -o dtbTool dtbTool.c

dtbSplit: dtbSplit.cpp
	$(CXX) -o dtbSplit -std=c++11 dtbSplit.cpp
