module libos.libdeepmajik.threadscheduler;

import libos.libdeepmajik.umm;
import Syscall = user.syscall;

import user.types;

// bottle for error code
import user.ipc;

const ulong ThreadStackSize = 4096;

/*

	Background:


	Theory of Operation:



	Scheduling:

	Embedding dequeue in swap:

*/
align(1) struct XombThread {
	ubyte* rsp;

	//void *threadLocalStorage;
	//void * syscallBatchFrame;

	// Scheduler Data
	XombThread* next;

	/*
		R11 - address for the XombThread being scheduled (this)
		R10  - base address of the SchedQueue struct

		RAX - address for the XombThread pointed to by tail, belongs in R11's next pointer
	*/
	void schedule(){
		XombThread* foo = this;
		//Place on scheduler's thread stack.
		/*scheduler.addThread(foo)*/

	}

	static:

	XombThread* threadCreate(void* functionPointer, ulong arg1, ulong arg2 = 0, ulong arg3 = 0, ulong arg4 = 0, ulong arg5 = 0, ulong arg6 = 0){
		XombThread* thread = threadCreate(functionPointer);

		// add another function 'return' address to the stack
		thread.rsp -= 8;
		(cast(void function()*)thread.rsp)[6] = &argShim;

		// stick args in place of the 'callee saved' registers that get
		// popped.  argShim will place these into the 'argument passing'
		// registers so that functionPointer will get the intended
		// arguments, when argShim ret's to it
		(cast(ulong*)thread.rsp)[0] = arg1;
		(cast(ulong*)thread.rsp)[1] = arg2;
		(cast(ulong*)thread.rsp)[2] = arg3;
		(cast(ulong*)thread.rsp)[3] = arg4;
		(cast(ulong*)thread.rsp)[4] = arg5;
		(cast(ulong*)thread.rsp)[5] = arg6;

		return thread;
	}

	XombThread* threadCreate(void* functionPointer){
		ubyte* stackptr = UserspaceMemoryManager.getPage(true);

		XombThread* thread = cast(XombThread*)(stackptr + 4096 - XombThread.sizeof);

		thread.rsp = cast(ubyte*)thread - ulong.sizeof;
		*(cast(ulong*)thread.rsp) = cast(ulong) &threadExit;

		// decrement sp and write arg
		thread.rsp = cast(ubyte*)thread.rsp - ulong.sizeof;
		*(cast(ulong*)thread.rsp) = cast(ulong) functionPointer;

		// space for 6 callee saved registers so new threads look like any other
		thread.rsp = cast(ubyte*)thread.rsp - (6*ulong.sizeof);

		return thread;
	}

	// WARNING: deep magic will fail silently if there is no thread
	// Based on the assumption of a 4kstack and that the thread struct is at the top of the stack
	XombThread* getCurrentThread(){
		XombThread* thread;

		asm{
			mov thread,RSP;
		}

		thread = cast(XombThread*)( (cast(ulong)thread & ~0xFFFUL) | (4096 - XombThread.sizeof) );

		return thread;
	}

	/*
		R10 - base address of the SchedQueue struct
		R11 - address for the XombThread being scheduled (this)

		RAX - address for the XombThread pointed to by tail, belongs in R11's next pointer

		R9  - temp for head of queue
		R8  - temp for tail of queue
	 */

	void threadYield(){
		//Add current thread to the MARKET scheduler, enter the OLD scheduler.
		XombThread* thread = getCurrentThread();
		/*TODO Add to Market scheduler as "schedulable"*/
		thread.schedule();
		_enterThreadScheduler();
		
	}


	/*
		R10 - base address of the SchedQueue struct
		R11 - address for the XombThread being enqueued (from getCurrentThread)

		RAX - address for the XombThread pointed to by tail, belongs in R11's next pointer

		RDI & RSI - location of arguments; shouldn't get clobbered, so they can be passed to Syscall.yield
	*/
	void yieldToAddressSpace(AddressSpace as, ulong idx){
		asm{
			naked;

			pushq RDI;
			pushq RSI;

			// save stack ready to ret
			call getCurrentThread;
			mov R11, RAX;

			popq RSI;
			popq RDI;

			mov R10, [queuePtr];

			pushq RBX;
			pushq RBP;
			pushq R12;
			pushq R13;
			pushq R14;
			pushq R15;

			mov [R11+XombThread.rsp.offsetof], RSP;

			// stuff old thread onto schedQueueTail
		start_enqueue:
			mov RAX, [R10 + tailOffset];

		restart_enqueue:
			mov [R11 + XombThread.next.offsetof], RAX;

			lock;
			cmpxchg [R10 + tailOffset], R11;
			jnz restart_enqueue;

			jmp Syscall.yield;
		}
	}


	void threadExit(){
		XombThread* thread = getCurrentThread();

		asm{
			lock;
			dec numThreads;
		}

		// schedule next thread or exit hw thread or exit if no threadsleft
		if(numThreads == 0){
			assert(schedQueueStorage.head == schedQueueStorage.tail && schedQueueStorage.tail == schedQueueStorage.tail2);

			Syscall.yield(null, 2UL);
		}else{
			//freePage(cast(ubyte*)(cast(ulong)thread & (~ 0xFFFUL)));

			asm{
				jmp _enterThreadScheduler;
			}
		}
	}


	/*
		R10 - base address of the SchedQueue struct

		RAX - a snapshot of head -- if not null, the thread that will be dequeued
		RDX - a snapshot of tail

		R11 - thread pointed to by RAX's next -- proposed head for if dequeue succeeds

		RBX - proposed head for if swap succeeds
		RCX - proposed tail for if swap succeeds
	*/

	// don't call this function :) certainly, not from a thread
	void _enterThreadScheduler(){
		asm{
			naked;
			mov R10, [queuePtr];

		load_head_and_tail:
			mov RAX, [R10 + headOffset];
		load_tail:
			mov RDX, [R10 + tailOffset];

			// assumes RAX and RDX are set
		null_checks:
			// if head is not null just dequeue, no swap is needed
			cmp RAX, 0;
			jnz dequeue;

			// if tail is also null, cpu is uneeded, so yield
			// FUTURE: might decide to _create_ a thread for task queue or idle/background work
			cmp RDX, 0;
			// XXX: requires a stack?
			mov RDI, 0;
			mov RSI, 1;
			jz Syscall.yield;


			// assumes RAX and RDX are set
		swap_and_dequeue:
			// the swap
			mov RBX, RDX;
			mov RCX, RAX;

			// integrated dequeue -- if swap succeeds, replace proposed head with it's own next
			mov RBX, [RBX + XombThread.next.offsetof];

			// If RDX:RAX still equals tail:head, set ZF and copy RCX:RBX to tail:head. Else copy tail:head to RDX:RAX and clear ZF.
			lock;
			cmpxchg16b [R10];
			jnz null_checks;
			// otherwise, we suceeded in swapping AND dequeuing what was tail and is now head
			mov RAX, RDX;
			jmp enter_thread;


			// assumes RAX is set
		dequeue:
			mov R11, [RAX + XombThread.next.offsetof];

			lock;
			// if RAX still equals head, set head to R11 and set ZF; else, store head in RAX and unset ZF
			cmpxchg [R10 + headOffset], R11;
			jnz load_tail;


			// assumes RAX is set
		enter_thread:
			mov RSP,[RAX+XombThread.rsp.offsetof];

			popq R15;
			popq R14;
			popq R13;
			popq R12;
			popq RBP;
			popq RBX;

			ret;
		}
	}

	//XXX: this are dumb.  should go away when 16 byte struct alignment works properly
	void initialize(){
		queuePtr = (cast(ulong)(&schedQueueStorage) % 16) != 0 ? (&schedQueueStorage + 8) : (&schedQueueStorage);
	}

private:
	void argShim(){
		asm{
			naked;

			// destinations are the x64 ABI's expected locations for arguments 1-6 in order
			mov RDI, R15;
			mov RSI, R14;
			mov RDX, R13;
			mov RCX, R12;
			mov R8,  RBP;
			mov R9,  RBX;

			ret;
		}
	}

	align(1) struct Queue{
		XombThread* head;
		XombThread* tail;
		XombThread* tail2;
	}

	static assert(schedQueueStorage.head.alignof >= 8);

	Queue schedQueueStorage;

	Queue* queuePtr;
	const uint headOffset = 0, tailOffset = ulong.sizeof;

	uint numThreads = 0;
}

void exit(int err){
	MessageInAbottle* bottle = MessageInAbottle.getMyBottle();

	bottle.exitCode = err;

	XombThread.threadExit();
}
