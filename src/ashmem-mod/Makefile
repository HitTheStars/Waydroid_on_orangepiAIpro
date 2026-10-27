obj-m := ashmem_mod.o
ashmem_mod-y := ashmem_main.o shim.o
ccflags-y += -I$(src)
ccflags-y += -include $(src)/shim.h
KDIR ?= /lib/modules/$(shell uname -r)/build
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
.PHONY: all clean
