package main

import "core:fmt"
import "core:mem"

main :: proc() {
	owner, err := owner_make(fmt.tprintf("order=%d", 7), context.allocator)
	if err != nil {
		fmt.eprintln("could not clone formatted order: ", err)
		return
	}
	defer owner_destroy(&owner)

	// Resetting temporary storage does not invalidate owner's clone.
	_ = mem.free_all(context.temp_allocator)
	fmt.println(owner.value)

}
