/**
 * Copyright (c) 1995 Gensym Corporation.  All Rights Reserved.
 *
 * Module:      tl.c
 *
 * Copyright (c) 1999 The Thinlisp Group
 * All Rights Reserved.
 *
 * This file is part of ThinLisp.
 *
 * ThinLisp is open source; you can redistribute it and/or modify it
 * under the terms of the ThinLisp License as published by the ThinLisp
 * Group; either version 1 or (at your option) any later version.
 *
 * ThinLisp is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 *
 * For additional information see <http://www.thinlisp.org/>
 *
 * Author   Jim Allard
 *
 * All of the Hand written functions and variables to support TL translated C
 * code are included here.  All other C code is generated by the translator
 * itself.
 */

#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/times.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>
#include <time.h>

#ifdef PTHREAD
#include <pthread.h>
#endif

#include "tl.h"


Thread_state default_thread_state;

uint32 default_thread_id = 0;

int thread_states_length = 0;

Thread_state *thread_states = NULL;

/** 
 * The function current_thread_state looks up and returns the thread_state in
 * effect for this thread.  Note that thread_states are created lazily, since
 * many short-lived threads will never need one.  Note that all calls to this
 * function should originate from the macro THREAD_STATE in tl.h, and that it is
 * never called unless the macro PTHREAD is defined.  
 */

#ifdef PTHREAD
#define NEW_THREADS_INC 20
Thread_state *new_thread_state(uint32 new_id, int new_index) {
  Thread_state *ts;
  Thread_state *new_array;

  ts = (Thread_state *)malloc(sizeof(Thread_state));
  ts->thread_id = new_id;
  ts->values_count = 0;
  ts->throw_stack_top = -1;
  ts->current_throw = NULL;
  ts->global_bindings = NULL;
  ts->parent_thread_state = NULL;
  if (new_index == -1) {
    new_index = thread_states_length;
    thread_states_length += NEW_THREADS_INC;
    new_array = (Thread_state *)malloc(thread_states_length * 
				       sizeof(Thread_state *));
    if (new_index != 0) {
      memcpy((void *)new_array, (void *)thread_states,
	     new_index * sizeof(Thread_state *));
      free(thread_states);
    }
  }
  ts->thread_index = new_index;
  thread_states[new_index] = ts;
  return ts;
}
Thread_state *current_thread_state(void) {
  int i, earliest_null;
  Thread_state *ts;
  uint32 current_thread_id = (uint32)pthread_self();

  if (default_thread_id == current_thread_id) {
    return &default_thread_state;
  } else {
    earliest_null = -1;
    for (i = 0; i < thread_states_length; ++i) {
      ts = thread_states[i];
      if (ts == NULL) {
	if (earliest_null == -1)
	  earliest_null = i;
      } else if (ts->thread_id == current_thread_id) {
	return ts;
      }
    }
    /* If we get here, no thread_state was found, create one. */
    return new_thread_state(earliest_null);
  }
}

void delete_thread_state(Thread_state *condemned) {
  Binding b = condemned->global_bindings;
  thread_states[condemned->thread_index] = NULL;
  while (b != NULL) {}
}
#endif


/**
 * Unbound Variables
 *
 * When a variable is defined but has not yet received an initial value, it is
 * unbound.  That will be represented in TL tranlated code as a pointer to the
 * unbound value.  This section implements the global C variable that will
 * contain the unbound value.  It is implemented as a Hdr struct that has the
 * type tag 14, which is reserved for the special type of unbound value.  */

Hdr Unbound = {14, 0};


/**
 * Global Lisp Stack
 *
 * The global variables Throw_stack and Throw_stack_top are used to
 * implement a global stack for storing environment information needed to
 * unwind state during non-local exits.  Global variable bindings, jmp_buf
 * pointers for throws, unwind protect scopes, and cached Values_buffers
 * are stored on this stack.  Throw_stack is an Obj array, and
 * Throw_stack_top is an sint32 indexing to the top-most filled value in
 * Throw_stack.  All entries in the stack are pushed onto the stack so that
 * they can be walked from the top of the stack back down towards the
 * bottom.  This is needed so that throws can unwind scopes as they search
 * for applicable catch targets.
 */

extern void store_values_on_stack (Obj first_value) {
  sint32 new_top, values;

  values = Values_count;
  new_top = Throw_stack_top + values + 2;
  Throw_stack_top = new_top;
  Throw_stack[new_top] = (Obj)1;
  Throw_stack[new_top - 1] = (Obj)values;
  if (values>0) {
    Throw_stack[(new_top - 1) - values] = first_value;
    if (values>1)
      memcpy((void *)&(Throw_stack[new_top - values]),
	     (void *)Values_buffer,
	     (values - 1) * sizeof(Obj));
  }
  return;
}

Obj retrieve_values_from_stack(void) {
  sint32 values, top;

  top = Throw_stack_top;
  if ((int)(Throw_stack[top]) != 1)
    error("Cannot retrieve values from stack.");
  values = (sint32)(Throw_stack[top - 1]);
  Throw_stack_top = (top - 2) - values;
  Values_count = values;
  if (values == 0) {
    return NULL;
  } else {
    if (values>1)
      memcpy((void *)&(Values_buffer[0]),
	     (void *)&(Throw_stack[top - values]),
	     (values - 1) * sizeof(Obj));
    return Throw_stack[(top - 1) - values];
  }
}

void throw_towards_catch_tag(Obj throw_tag, Obj first_value) {
  sint32 index = Throw_stack_top;
  int stack_entry_type;
  jmp_buf *target_jmp_buf;

  while (index>=0) {
    stack_entry_type = (int)(Throw_stack[index]);
    switch (stack_entry_type) {
      /* Global variable binding, unbind it and skip down three. */
    case 0:
      *((Obj *)(Throw_stack[index - 1])) = Throw_stack[index - 2];
      index = index - 3;
      break;
      /* Cached values, skip down 2 + the number of values. */
    case 1:
      index = (index - 2) - (sint32)(Throw_stack[index - 1]);
      break;
      /* An unwind-protect stands between us and the catch we want.  So, save
	 the throw tag and values, continue to search for the tag we want
	 erasing the tags of intervening catches that aren't what we want, and
	 jump to the unwind-protect.  See "Once you have begun to catch a crab,
	 you cannot rely on being able to catch your breath," CLtL 2,
	 pp. 190-191.  -jra 1/24/96 */
    case 3:
      Current_throw = throw_tag;
      target_jmp_buf = (jmp_buf *)(Throw_stack[index - 1]);
      Throw_stack_top = index - 2;
      store_values_on_stack(first_value);
      while (index>=0) {
	switch ((int)(Throw_stack[index])) {
	case 0:
	  index = index - 3;
	  break;
	case 1:
	  index = (index - 2) - (sint32)(Throw_stack[index - 1]);
	  break;
	case 3:
	  index = index - 2;
	  break;
	case 4:
	  if (throw_tag == Throw_stack[index - 1])
	    index = -1;		/* This stops our current while loop. */
	  else {
	    Throw_stack[index - 1] = (Obj)&Unbound;
	    index = index - 3;
	  }
	  break;
	default:
	  error("Bad throw stack marker");
	}
      }
      longjmp(*target_jmp_buf, 1);
      /* Catch, jump to it if the catch tag is eq, else pop 3. */
    case 4:
      if (throw_tag == Throw_stack[index - 1]) {
	target_jmp_buf = (jmp_buf *)(Throw_stack[index - 2]);
	Throw_stack_top = index - 3;
	store_values_on_stack(first_value);
	longjmp(*target_jmp_buf, 1);
      } else {
	index = index - 3;
	break;
      }
    default:
      error("Bad throw stack marker");
    }
  }
  error("Didn't find throw_tag");
}


/**
 * Memory allocation
 *
 * The function alloc_bytes takes a region number, an alignment value and a
 * number of bytes.  This function will return a void* aligned on the desired
 * boundary containing the required number of bytes.  Internally there is a set
 * of memory blocks per region sorted from smallest to largest.  Memory will be
 * taken from the smallest available block to be given to the user.
 *
 * The functions region_number_bytes_size, region_number_bytes_used, and
 * region_number_bytes_available take an sint32 region number (0, 1, or 2) and
 * return an sint32 number of bytes.  Region_size returns the number of bytes
 * malloced for a region.  Region_used returns the number of malloced bytes that
 * have been used.  Region_available is the difference between these two.
 *
 * The function malloc_block_into_region takes a region number and an sint32
 * number of bytes to allocate into the region.  When alloc_bytes needs more
 * memory, it will call malloc_block_into_region with the maximum of the memory
 * needed for the structure being made and 64K.
 * 
 * The sint32 variable Disable_region_blocks causes alloc_bytes to always call
 * malloc for each allocation.  This makes it possible to call free on the
 * allocated blocks of memory.  This can be changed for individual calls to
 * alloc_bytes.
 */

#define REGION_COUNT 3

#define PERMANENT_REGION 0

#define SYMBOL_REGION 1

#define TEMPORARY_REGION 2

#define MAXIMUM_NUMBER_OF_BLOCKS 3

#define DISCARDABLE_BLOCK_SIZE 12

#define DEFAULT_BLOCK_SIZE 65536

#define EMERGENCY_MEMORY_SIZE 16384 

#define BYTES_IN_BLOCK(region,block) ((sint32)((region==TEMPORARY_REGION?(unsigned long)Temporary_region_top:(unsigned long)((block)->top))-(unsigned long)((block)->base)))

typedef struct memory_block_type {
  struct memory_block_type *next_block;
  void          *base;
  void          *top;
} memory_block;

static memory_block *region_blocks[REGION_COUNT] = {NULL, NULL, NULL};

static unsigned long region_size[REGION_COUNT] = {0, 0, 0};

static unsigned long region_used[REGION_COUNT] = {0, 0, 0};

sint32 Disable_region_blocks = 0;

Obj Current_region = NULL;

Obj Temporary_region_top = NULL;

#define CURRENT_REGION_NUMBER ((sint32)Current_region >> 2)

static sint32 emergency_memory_used = 0;

static memory_block emergency_block;

static unsigned char emergency_memory[EMERGENCY_MEMORY_SIZE];

void discard_block (sint32 region, memory_block *block) {
  memory_block *current_block, *next_block;
  char msg[256];

  region_used[region] += ((unsigned long)block->top - 
			  (unsigned long)block->base);

  if (region_blocks[region] == block) {
    region_blocks[region] = block->next_block;
    return;
  } else {
    current_block = region_blocks[region];
    while ((next_block = current_block->next_block) != NULL) {
      if (next_block == block) {
	current_block->next_block = block->next_block;
	return;
      } else {
	current_block = next_block;
      }
    }
    sprintf(msg, "TL Memory Error: Couldn't find block %lx to discard from region %d.",
	    (unsigned long)block, (int)region);
    fatal_error(msg);
  }
}

sint32 blocks_in_region (sint32 region) {
  sint32 count = 0;
  memory_block *block = region_blocks[region];

  while (block != NULL) {
    count++;
    block = block->next_block;
  }
  return count;
}

void malloc_block_into_region (sint32 region, sint32 byte_count, sint32 silent) {
  memory_block *new_block, *current_block, *next_block;
  void *new_memory;
  char msg[512];

  /* Malloc memory for the new block and the requested byte_count. */
  new_block = (memory_block *)malloc(sizeof(memory_block));
  new_memory = malloc(byte_count);

  /* If either malloc failed, attempt to use emergency memory, else exit. */
  if (new_block == NULL || new_memory == NULL) {
    sprintf(msg,
	    "Out of swap space, failed to obtain %d bytes of memory for region %d.\n",
	    (int)byte_count, (int)region);
    if (emergency_memory_used == 0) {
      emergency_memory_used = 1;
      new_block = &emergency_block;
      new_memory = (void *)emergency_memory;
      byte_count = EMERGENCY_MEMORY_SIZE;
      sprintf(strchr(msg,0),
	      "Obtained the %d bytes of emergency memory for region %d.  Unless more\n",
	      EMERGENCY_MEMORY_SIZE, (int)region);
      sprintf(strchr(msg,0),
	      "swap space becomes available, the next attempt to obtain more memory\n");
      sprintf(strchr(msg,0),
	      "will also fail, and this program will exit.\n");
      warn(msg);
    } else {
      sprintf(strchr(msg,0),
	      "All emergency memory has already been used, this program must exit.\n");
      fatal_error(msg);
    }
  }

  new_block->base = new_memory;

  if (blocks_in_region(region) >= MAXIMUM_NUMBER_OF_BLOCKS)
    discard_block(region, region_blocks[region]);

  new_block->top = (void *)((unsigned long)new_memory + byte_count);
  if (region == TEMPORARY_REGION)
    Temporary_region_top = (Obj)(new_block->top);
  region_size[region] += byte_count+sizeof(memory_block);
  region_used[region] += sizeof(memory_block);

  if (silent == 0) {
    sprintf(msg,"Obtaining more memory (region %d at %ld)\n",
	    (int)region, (long)(region_used[region]));
    notify(msg);
  }

  /* Insert the new block into the region, smallest blocks first. */
  
  current_block = region_blocks[region];
  if (current_block == NULL ||
      byte_count <= BYTES_IN_BLOCK(region,current_block)) {
    region_blocks[region] = new_block;
    new_block->next_block = current_block;
  } else {
    while ((next_block = current_block->next_block) != NULL &&
	   byte_count < BYTES_IN_BLOCK(region,next_block))
      current_block = next_block;
    current_block->next_block = new_block;
    new_block->next_block = next_block;
  }
  return;
}

sint32 region_number_bytes_size (sint32 region) {
  return region_size[region];
}

sint32 region_number_bytes_used (sint32 region) {
  return region_used[region];
}

sint32 region_number_bytes_available (sint32 region) {
  return region_size[region] - region_used[region];
}

sint32 bytes_in_first_block_of_region (sint32 region) {
  memory_block *first_block;
  
  if ((first_block=region_blocks[region]) == NULL)
    return 0;
  else
    return BYTES_IN_BLOCK(region,first_block);
}

void *alloc_bytes(sint32 region, sint32 alignment, sint32 bytes) {
  memory_block *block;
  unsigned long base, top, old_top;
  sint32 attempts;
  void *malloced;

  if (Disable_region_blocks != 0) {
    /* At this call to malloc, we will want to set a bit in a memory_map table
       so we can validate calls to free.  -jra 2/29/96 */
    malloced = malloc(bytes);
    if (malloced == NULL)
      fatal_error("Out of swap space.");
    region_used[region] += bytes;
    region_size[region] += bytes;
    return malloced;
  }

  for (attempts=1; attempts<3; attempts++) {
    block = region_blocks[region];
    while (block != NULL) {
      base = (unsigned long)block->base;
      old_top = (region == TEMPORARY_REGION 
		 ? (unsigned long)Temporary_region_top
		 : (unsigned long)(block->top));
      /* Subtract off the needed bytes from old_top, and then align by rounding
	 down using the bitwise AND operation. */
      top = (old_top - bytes) & -(long)alignment;
      if (top >= base) {
	block->top = (void *)top;
	if (region==TEMPORARY_REGION)
	  Temporary_region_top = (Obj)top;
	else {
	  region_used[region] += (sint32)(old_top - top);
	  if (BYTES_IN_BLOCK(region,block) <= DISCARDABLE_BLOCK_SIZE)
	    discard_block(region,block);
	}
	return (void *)top;
      } else {
	if (region==TEMPORARY_REGION)
	  fatal_error("Internal error in alloc_bytes, ran out of space in temporary region.");
	block = block->next_block;
      }
    }
    malloc_block_into_region 
      (region, DEFAULT_BLOCK_SIZE < bytes ? bytes : DEFAULT_BLOCK_SIZE, 0);
  }
  fatal_error("Internal error in alloc_bytes, failed after second attempt.");
  return NULL; /* Unreachable, needed to squelch compiler warning. */
}

void bad_region_warning(sint32 region, char *type) {
  char message[256];

  sprintf(message,"Allocating %s from region %d when %d was expected.",
	  type, (int)CURRENT_REGION_NUMBER, (int)region);
  warn(message);
}

Obj alloc_cons (Obj new_car, Obj new_cdr, sint32 region) {
  Cons *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "Pair");
    region = CURRENT_REGION_NUMBER;
  }
  new = (Cons *)alloc_bytes(region, 4, sizeof(Cons));
  new->car = new_car;
  new->cdr = new_cdr;
  return (Obj)((uint32)new + 2);
}



/**
 * The function hook_up_cdrs takes an array of conses, hooks up the cdrs of
 * each cons to the next cons in the array, and then sets the cdr of the final
 * cons in the array to NIL.  An Obj format pointer to the first cons is
 * returned.  Count must be positive.
 */

Obj hook_up_cdrs (Obj *car_cdr_array, sint32 count, Obj final_cdr) {
  sint32 index;
  sint32 max_index = count-1;
  Cons *cons_array;

  cons_array = (Cons *)car_cdr_array;
  for (index = 0; index<max_index; index++)
    cons_array[index].cdr = (Obj)((uint32)(&cons_array[index+1]) + 2);
  cons_array[max_index].cdr = final_cdr;
  return (Obj)((uint32)car_cdr_array + 2);
}

Obj alloc_list (sint32 length, sint32 init_cars_p, Obj init_elt, sint32 region) {
  Obj last_cdr, first_cons;
  Cons *cons_to_init;
  sint32 bytes_available, conses_available, alloc_count, index;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "List");
    region = CURRENT_REGION_NUMBER;
  }
  first_cons = NULL;
  while (length>0) {
    last_cdr = first_cons;
    bytes_available = bytes_in_first_block_of_region(region);
    conses_available = bytes_available/sizeof(Cons);
    
    if (conses_available>=length || conses_available==0)
      alloc_count = length;
    else 
      alloc_count = conses_available;

    cons_to_init = (Cons *)alloc_bytes(region, 4, alloc_count*sizeof(Cons));

    /* Initialize the cdrs, then if required, initialize the cars to the given 
     * value.
     */
    first_cons = hook_up_cdrs((Obj *)cons_to_init, alloc_count, last_cdr);

    if (init_cars_p) {
      for (index=0; index<alloc_count; index++)
	cons_to_init[index].car = init_elt;
    }

    length = length - alloc_count;
  }

  return first_cons;
}

Obj alloc_simple_vector (sint32 length, sint32 region, sint32 type_tag) {
  Sv *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "Sv");
    region = CURRENT_REGION_NUMBER;
  }

  /* By default the Sv struct contains 1 element. */
  new = (Sv *)alloc_bytes(region, 4, 
			  sizeof(Sv)+(length<1 ? 0 : (length-1)*sizeof(Obj)));
  new->type = type_tag;
  new->length = length;
  return (Obj)new;
}

Obj alloc_string (sint32 dimension, sint32 region, sint32 type_tag) {
  Str *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "Str");
    region = CURRENT_REGION_NUMBER;
  }

  /* By default the Str struct contains 9 bytes, one of which is needed for the
     terminating NULL byte of the string. */ 
  new = (Str *)alloc_bytes(region, 4, sizeof(Str)+dimension-8);
  new->type = type_tag;
  new->length = dimension;
  new->fill_length = dimension;
  new->body[dimension] = '\000';
  return (Obj)new;
}

Obj alloc_uint8_array (sint32 length, sint32 region, sint32 type_tag) {
  Sa_uint8 *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1) 
      bad_region_warning(region, "Sa_uint8");
    region = CURRENT_REGION_NUMBER;
  }
  /* By default the Sa_uint8 struct contains 4 elements. */
  new = (Sa_uint8 *)alloc_bytes(region, 4, sizeof(Sa_uint8)+(length-4));
  new->type = type_tag;
  new->length = length;
  new->fill_length = length;
  return (Obj)new;
}

Obj alloc_uint16_array (sint32 length, sint32 region, sint32 type_tag) {
  Sa_uint16 *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "Sa_uint16");
    region = CURRENT_REGION_NUMBER;
  }
  /* By default the Sa_uint16 struct contains 2 elements. */
  new = (Sa_uint16 *)alloc_bytes(region, 4, sizeof(Sa_uint16)+((length-2)*sizeof(uint16)));
  new->type = type_tag;
  new->length = length;
  new->fill_length = length;
  return (Obj)new;
}

Obj alloc_double_array (sint32 length, sint32 region, sint32 type_tag) {
  Sa_double *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "Sv");
    region = CURRENT_REGION_NUMBER;
  }
  /* By default the Sa_double struct contains 1 element. */
  new = (Sa_double *)alloc_bytes(region, 8, sizeof(Sa_double)+((length-1)*sizeof(double)));
  new->type = type_tag;
  new->length = length;
  return (Obj)new;
}

Obj alloc_ldouble (double new_value, sint32 region, sint32 type_tag) {
  Ldouble *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "Ldouble");
    region = CURRENT_REGION_NUMBER;
  }
  new = (Ldouble *)alloc_bytes(region, 8, sizeof(Ldouble));
  new->type = type_tag;
  new->body = new_value;
  return (Obj)new;
}

Obj alloc_mdouble (double new_value, sint32 region, sint32 type_tag) {
  Mdouble *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "Mdouble");
    region = CURRENT_REGION_NUMBER;
  }

  new = (Mdouble *)alloc_bytes(region, 8, sizeof(Mdouble));
  new->type = type_tag;
  new->body.value = new_value;
  return (Obj)new;
}

Obj alloc_symbol (sint32 region, sint32 type_tag) {
  Sym *new;

  if (region!=CURRENT_REGION_NUMBER && region!=SYMBOL_REGION) {
    if (region != -1)
      bad_region_warning(region, "Sym");
    region = CURRENT_REGION_NUMBER;
  }

  new = (Sym *)alloc_bytes(region, 4, sizeof(Sym));
  new->type = type_tag;
  return (Obj)new;
}

Sym T;

Obj alloc_package (Obj name_string, Obj used, sint32 region, sint32 type_tag) {
  Pkg *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "Pkg");
    region = CURRENT_REGION_NUMBER;
  }

  new = (Pkg *)alloc_bytes(region, 4, sizeof(Pkg));
  new->type = type_tag;
  new->name = name_string;
  new->root_symbol = (Obj)&Unbound;
  new->used_packages = used;
  return (Obj)new;
}

Obj alloc_string_strm (sint32 region, sint32 type_tag) {
  String_strm *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "String_strm");
    region = CURRENT_REGION_NUMBER;
  }

  new = (String_strm *)alloc_bytes(region, 4, sizeof(String_strm));
  new->type = type_tag;
  new->strings = NULL;
  new->input_string = NULL;
  new->input_index = 0;
  new->input_index_bounds = 0;
  return (Obj)new;
}

Obj alloc_file_strm (FILE *input, FILE *output, char *filename,
			   char *mode, sint32 region, sint32 type_tag) {
  File_strm *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "File_strm");
    region = CURRENT_REGION_NUMBER;
  }

  new = (File_strm *)alloc_bytes(region, 4, sizeof(File_strm));
  new->type = type_tag;
  new->input = input;
  new->output = output;
  new->filename = filename ;
  new->mode = mode;
  return (Obj)new;
}


/**
 * The function alloc_struct is used to malloc a new structure
 * instance.  The total number of required bytes is passed as the
 * first argument.  The byte alignment is passed as the second arg.
 * The byte alignment for a structure will vary depending on the types
 * of the elements of the structure.  Usually it will be 4 byte
 * aligned, but there is a double as a element of the structure, then
 * the alignment will be 8 bytes.  The allocation region and type tag
 * are passed last.  Note that for structures, the lower 8 bits of the
 * header should always be the same value, CLASS_HDR_TAG, and that the
 * upper 24 bits will hold the actual tag, i.e. the extended_type of
 * the Class_hdr structure. 
 */

Obj alloc_struct (sint32 bytes, sint32 align, sint32 region, sint32 type_tag) {
  Class_hdr *new;

  if (region!=CURRENT_REGION_NUMBER) {
    if (region != -1)
      bad_region_warning(region, "Struct");
    region = CURRENT_REGION_NUMBER;
  }

  new = (Class_hdr *)alloc_bytes(region, align, bytes);
  new->type = CLASS_HDR_TAG;
  new->extended_type = type_tag;
  return (Obj)new;
}


/**
 * sint32 get_platform_code() 
 *
 * This function is called from Lisp to initialize the variables g2-machine-type
 * and g2-operating-system in BOOTSTRAP.  It returns a long which describes the
 * platform in which this image is running.
 *
 * Previously, this was done in /bt/ab/g2/c/g2main.c, but this code doesn't
 * belong there, since the translator now generates a main() file automatically
 * and there is no reason we can't initialize g2-machine-type and
 * g2-operating-system as we do any other defvars.
 *
 * Note that some of the C preprocessor switches are "hardwired" into the C
 * proprocessor (e.g., unix), and we at Gensym supply others to the C
 * preprocessor via a -D command-line option or its equivalent (e.g., sparcsol).
 *
 * 8/17/93, jh: As of this date, to add a new platform xxx, #define a unique
 * code number for xxx_CODE below, then add an #ifdef or #if clause below,
 * making sure that no other clause gets triggered.  The association of a given
 * platform with its operating system happens on the Lisp side, in the module
 * BOOTSTRAP.  Go to the comments there to finish adding a new platform.
 *
 * 9/28/93, mpc: Changed platform identifier __ALPHA below to (__ALPHA) &&
 * (vms). This is because the __ALPHA flag is defined by both the vms and NT
 * compilers.  */

#define I386_CODE         1
#define DOS_CODE          2
#define AVIION_CODE       3
#define SGI_CODE          4
#define SEQUENT_CODE      5
#define NEXT_CODE         6
#define DECSTATION_CODE   7
#define MASSCOMP_CODE     8
#define HP9000S300_CODE   9
#define HP9000S400_CODE  10
#define HP9000S700_CODE  11
#define HP9000S800_CODE  12
#define RS6000_CODE      13
#define SUN3_CODE        14
#define SUN4_CODE        15
#define SPARCSOL_CODE    16
#define ALPHAVMS_CODE    17
#define MOTOROLA_CODE    18
#define VMS_CODE         19
#define STRATUS_CODE     20
#define HARRIS_CODE      21
#define NEC_CODE         22
#define ALPHAOSF_CODE    23
#define ALPHANT_CODE     24
#define INTELNT_CODE     25
#define NCR_CODE         26
#define WINDOWS95_CODE   27
#define FREEBSD_CODE     28
#define LINUX386_CODE    29

sint32 get_platform_code(void) {
    sint32 platform_code = 0;

#    if defined(i386) && !defined(_SEQUENT_)
         platform_code = I386_CODE;
#    endif

#    ifdef __WATCOMC__
         platform_code = DOS_CODE;
#    endif

#    ifdef DGUX
         platform_code = AVIION_CODE;
#    endif

#    ifdef sgi
         platform_code = SGI_CODE;
#    endif

#    ifdef _SEQUENT_
         platform_code = SEQUENT_CODE;
#    endif

#    ifdef NeXT
         platform_code = NEXT_CODE;
#    endif

#    if defined(mips) && !defined(sgi)
         platform_code = DECSTATION_CODE;
#    endif

#    ifdef masscomp
         platform_code = MASSCOMP_CODE;
#    endif

#    ifdef hp9000s300
         platform_code = HP9000S300_CODE;
#    endif

#    ifdef hp9000s400
         platform_code = HP9000S400_CODE;
#    endif

#    ifdef __hp9000s700
         platform_code = HP9000S700_CODE;
#    endif

#    if defined(hp9000s800) && !defined(__hp9000s700)
         platform_code = HP9000S800_CODE;
#    endif

#    ifdef _IBMR2
         platform_code = RS6000_CODE;
#    endif

#    if defined(sun) && !defined(sparc)
         platform_code = SUN3_CODE;
#    endif

#    ifdef sun4
         platform_code = SUN4_CODE;
#    endif

#    ifdef sparcsol
         platform_code = SPARCSOL_CODE;
#    endif

#    ifdef alphavms
         platform_code = ALPHAVMS_CODE;
#    endif

#    ifdef motorola
         platform_code = MOTOROLA_CODE;
#    endif

#    ifdef _nst
         platform_code = NCR_CODE;
#    endif

#    ifdef vax
         platform_code = VMS_CODE;
#    endif

#    ifdef _FTX
         platform_code = STRATUS_CODE;
#    endif

#    ifdef _CX_UX
         platform_code = HARRIS_CODE;
#    endif

#    ifdef nec
         platform_code = NEC_CODE;
#    endif

#    ifdef __osf__
         platform_code = ALPHAOSF_CODE;
#    endif

#    ifdef _WIN32
#        ifdef __ALPHA
             platform_code = ALPHANT_CODE;
#        elif defined(__CYGWIN__)
	     platform_code = WINDOWS95_CODE;
#        else
             if (GetVersion() < 0x80000000) {
		 /* Windows NT */
		 platform_code = INTELNT_CODE;
	     } else if (LOBYTE(LOWORD(GetVersion())) < 4) {
		 /* Win32s on Windows 3.1 */
		 platform_code =  DOS_CODE;
	     } else {
		 /* Chicago / Windows95 */
		 platform_code = WINDOWS95_CODE;
	     }
#        endif
#    endif

#    ifdef __FreeBSD__
         platform_code = FREEBSD_CODE;
#    endif

#    ifdef __linux__
	 platform_code = LINUX386_CODE;
#    endif

    return platform_code;
}


/**
 * The function cc_g2_stream_delete_file deletes files, handling platform
 * differences.  It takes a char * and returns 0 for success and -1 for failure.
 */

sint32 delete_named_file(char *filename) {
#if defined(vms)
  long success_code = delete(filename);
#else
  long success_code = unlink(filename);
#endif

  if (success_code == 0)
    return(0);
  else
    return(-1);
}

/* On the Sun, we have warnings turned way up, and the standard Sun include file
 * time.h doesn't have a declaration for time(). 
 */

#if defined(sun4)
extern time_t time(time_t *timeptr);
#endif


/**
 * User Notification Functions
 *
 * The functions notify, warn, error, and fatal_error all take a char*
 * containing the message to deliver.  Each then performs slightly different
 * wrapping message behavior or exits.
 */

static char *current_time_string(void) {
  time_t now;

  now = time(NULL);
  return ctime(&now);
}

void notify (char *message) {
  printf("%s%s\n", current_time_string(), message);
  return;
}

void warn (char *message) {
  printf("%s**** WARNING ****\n%s\n", current_time_string(), message);
  return;
}

void error (char *message) {
  /* Insert throw calls here instead of exit.  -jra 12/18/95 */
  fatal_error(message);
}

void type_cast_error(char *source_type, char *target_type) {
  char error_message[256];
  sprintf(error_message,"Unable to coerce type %s to type %s.", 
	  source_type, target_type);
  error(error_message);
}

void fatal_error (char *message) {
  printf("%s**** ERROR ****\n%s\n", current_time_string(), message);
  exit(1);
}


/**
 * Formatting Tools
 *
 * The functions in this section implement printing primitives into
 * fill-pointered strings.  Each of these functions takes an Str struct that
 * should have enough room to hold the formatting of the given value, and a
 * value to print.  If there is not enough room in the string given, then these
 * functions should call error.  The functions are write_string_into_str,
 * write_char_into_str, write_fixnum_into_str, and write_double_into_str.
 */

void write_fixnum_into_str (sint32 value, sint32 width, Str *output) {
  char *base, *current_end, *new_end;

  base = (char *)(output->body);
  current_end = base + output->fill_length;

  if (width > 0)
    sprintf(current_end, "%*ld", (int)width, (long)value);
  else
    sprintf(current_end, "%ld", (long)value);
  new_end = strchr(current_end, 0);

  if (new_end > base + output->length)
    error("Overflow in write_string_into_str.");

  output->fill_length = (uint32)new_end - (uint32)base;
  return;
}

void write_double_into_str (double value, sint32 width, Str *output) {
  char *base, *current_end, *new_end;

  base = (char *)(output->body);
  current_end = base + output->fill_length;

  if (width > 0)
    sprintf(current_end, "%*g", (int)width, value);
  else
    sprintf(current_end, "%g", value);
  new_end = strchr(current_end, 0);

  if (new_end > base + output->length)
    error("Overflow in write_string_into_str.");

  output->fill_length = (uint32)new_end - (uint32)base;
  return;
}


/**
 * The following functions implement the get-internal-real-time primitives.  The
 * initialization function should cache the result of an initial call to times
 * and take the difference between that and any subsequent calls.  This will
 * make the returned value always start from zero and count up.
 */

static clock_t base_cron;

/*
 * Linux has bolluxed up the definition of CLOCKS_PER_SEC, saying that this
 * value must be 1000000 to be compliant with a standard, even though that is
 * the wrong value if you look at what the time functions actually do.  Just set
 * it to 100 for Linux, that is correct for the i386 port, though it may be
 * wrong for the Alpha port.  -jallard 1/11/00 
 */

#ifdef __linux__
#define TICKS 100
#else
#define TICKS CLOCKS_PER_SEC
#endif

extern void init_cronometer(void) {
  struct tms time_buf;
  base_cron = times(&time_buf);
}

extern sint32 cronometer(void) {
  struct tms time_buf;

  return (sint32)(times(&time_buf) - base_cron);
}

extern sint32 cpu_run_time(void) {
  struct tms buf;
  
  times(&buf);
  return (sint32)(buf.tms_utime + buf.tms_stime + 
		  buf.tms_cutime + buf.tms_cstime);
}

extern sint32 ticks_per_second(void) {
  return (sint32)TICKS;
}

/*
extern void sleep_nanoticks(sint32 seconds) {
  struct timespec req, rem;
  if (seconds > 0) {
    time_t full_seconds;
    long nanos;

    full_seconds = (time_t)(seconds / TICKS);
    nanos = (long)(((double)(seconds % TICKS) / (double)TICKS)
		   * 1000000000.0);
    while (nanosleep(&req, &rem) == -1 && 
	   errno == EINTR &&
	   (rem.tv_sec > 0 || rm.tv_nsec > 0)) {
      req = rem;
    }
  }
}
*/


extern void sleep_ticks(sint32 seconds) {
  struct timeval tv;
  if (seconds > 0) {
    time_t full_seconds;
    long micros;

    full_seconds = (time_t)(seconds / TICKS);
    micros = (long)(((double)(seconds % TICKS) / (double)TICKS)
		   * 1000000.0);
    tv.tv_sec = full_seconds;
    tv.tv_usec = micros;
    select(0, NULL, NULL, NULL, &tv);
  }
}
    

