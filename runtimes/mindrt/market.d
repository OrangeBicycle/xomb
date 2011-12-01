import libos.libdeepmajik.threadscheduler; 

extern(C) void start3(char[][]);

Scheduler sch;
extern(C) void marketscheduler(ulong argvlen, ulong arvptr, ulong time=0) {
	if(time==1){
		sch.head = sch.tail = null;
		XombThread* mainThread = XombThread.threadCreate(&start3, argvlen, argvptr);
		mainThread.schedule();
	}
	XombThread* xt = sch.runThread();
}

struct Scheduler {
	Node* head;
	Node* tail;
	Node* maxBid = null;
	void removeThread(Node* n) {
		(*n.prev).next = n.next;
		(*n.next).prev = n.prev;
	}
	void addThread(XombThread* xt, uint bid=0) {
		if(head == null) {
			Node n;
			n.createNode(null, null, xt, bid);
			head = n;
			tail = n;
			if(maxBid == null) maxBid = n;
		}
		else {
			Node n;
			n.createNode(null, tail, xt, bid);
			tail.next = n;
			tail = n;
			if(maxBid == null || (*maxBid).bid < (*n).bid) maxBid = n;
		}
	}
	XombThread* runThread() {
		//Highest Bid
		removeThread(maxBid);
		return maxBid.data;
	}
}

struct Node {
	Node* next;
	Node* prev;
	XombThread* data;
	uint bid = 0;
	
	void createNode(Node* n, Node* p, XombThread* d, uint b=0) {
		next = n; prev = p; data = d; bid = b;
	}
	void updateBid(uint x) {
		bid = x;
	}
	uint getBid() {
		return bid;
	}
}
