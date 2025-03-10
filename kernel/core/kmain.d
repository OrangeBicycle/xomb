/* XOmB
 *
 * This is the main function for the XOmB Kernel
 *
 */

module kernel.core.kmain;

// Import the architecture-dependent interface
import architecture.cpu;
import architecture.multiprocessor;
import architecture.vm;
import architecture.syscall;
import architecture.main;
import architecture.perfmon;
import architecture.timing;

// This module contains our powerful kprintf function
import kernel.core.kprintf;
import kernel.core.log;
import kernel.core.error;

//handle everything that the boot loader gives us
import kernel.system.bootinfo;
import kernel.system.info;

// kernel heap
import kernel.mem.pageallocator;

import kernel.dev.console;
import kernel.dev.keyboard;
import kernel.dev.pci;

//import kernel.core.syscall;
import kernel.core.dispatcher;


// init process
import kernel.core.initprocess;

// The main function for the kernel.
// This will receive data from the boot loader.

// bootLoaderID is the unique identifier for a boot loader.
// data is a structure given by the boot loader.
extern(C) void kmain(int bootLoaderID, void *data) {

	//first, we'll print out some fun status messages.
	kprintfln!("{!cls!fg:White} Welcome to {!fg:Green}{}{!fg:White}! (version {}.{}.{})")("XOmB", 0,1,0);
	for(int i; i < 80; i++) {
		// 0xc4 -- horiz line
		// 0xcd -- double horiz line
		kprintf!("{}")(cast(char)0xcd);
	}


	// 1. Bootloader Validation
	Log.print("BootInfo: initialize()");
	Log.result(BootInfo.initialize(bootLoaderID, data));

	// 2. Architecture Initialization
	Log.print("Architecture: initialize()");
   	Log.result(Architecture.initialize());

	// 2b. Paging Initialization
	Log.print("VirtualMemory: initialize()");
   	Log.result(VirtualMemory.initialize());

	// 2c. Paging Install
	Log.print("VirtualMemory: install()");
	Log.result(VirtualMemory.install());

	Log.print("PerfMon: initialize()");
	Log.result(PerfMon.initialize());

	// 3. Processor Initialization
	Log.print("Cpu: initialize()");
	Log.result(Cpu.initialize());

	// 4a. Initialize the Page Allocator
	Log.print("PageAllocator: initialize()");
	Log.result(PageAllocator.initialize());

	// 4b. Console Initialization
	Log.print("Console: initialize()");
	Log.result(Console.initialize());

	// 5. Timer Initialization
	Log.print("Timing: initialize()");
	Log.result(Timing.initialize());

	// 6. Multiprocessor Initialization
	Log.print("Multiprocessor: initialize()");
	Log.result(Multiprocessor.initialize());
	kprintfln!("Number of Cores: {}")(Multiprocessor.cpuCount);

	// 7. Syscall Initialization
	Log.print("Syscall: initialize()");
	Log.result(Syscall.initialize());

	Log.print("Multiprocessor: bootCores()");
	Log.result(Multiprocessor.bootCores());

	Log.print("Keyboard: initialize()");
	Log.result(Keyboard.initialize());

	Log.print("PCI: initialize()");
	Log.result(ErrorVal.Fail);
	//Log.result(PCI.initialize());


	Log.print("Init Process: install()");
	auto fail = InitProcess.install();
	Log.result(fail);

	if(fail != ErrorVal.Fail){
		Date dt;

		Timing.currentDate(dt);
		kprintfln!("\nDate: {} {} {}")(dt.day, dt.month, dt.year);

		Dispatcher.initialize();

		InitProcess.enterFromBSP();
	}else{
		kprintfln!("\nCould not install init. I am giving up.")();
		for(;;){}
	}
	// Run task
	assert(false, "Something is VERY VERY WRONG. entering Init returned. :(");

	for(;;){}
}

extern(C) void apEntry() {

	// 0. Paging Initialization
	VirtualMemory.install();

	// 1. Processor Initialization
	Cpu.initialize();

	// 2. Core Initialization
	Multiprocessor.installCore();

	// 3. Syscall Initialization
	Log.print("Syscall: initialize()");
	Log.result(Syscall.initialize());

	// 4. Schedule
	//Scheduler.idleLoop();

	InitProcess.enterFromAP();
}
