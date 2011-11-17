module libos.libdeepmajik.marketscheduler;

import Syscall = user.syscall;

import user.types;

// bottle for error code
import user.ipc;

Node* head = null;
Node* tail = null;
int dq = 0;

enum {
        Highest,
        Second,
        Average,
        Lowest
        }

void schedule(XombThread* x) {
	Node n;
	n.createNode(0, null, null, x); //TEMPORARY
	insertNode(&n);
}

void insertNode(Node* n, int a) {
	switch(a) {
		case Highest:
			if ((*n).bid > (*dq).bid) dq = n;
			break;
		case Lowest:
			if((*n).bid < (*dq).bid) dq = n;
			break;
		case Second:
		case Average:
		case default:
			dq = n; 
			break;
	if(head is null) {
		head = n;
		tail = n;
	}
	else {
		(*tail).next = n;
		(*n).prev = tail;
		tail = n;
	}
}

//void dequeNode(Node* n, Alg a) {

//}

struct Node {
	int bid = 0;
	Node* next;
	Node* prev;
	XombThread* thd;
	void createNode(int b, Node* n, Node* p, XombThread* t) {
		next = n;
		prev = p;
		bid  = b;
		thd  = t;
	};
}
