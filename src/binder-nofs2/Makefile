obj-m := binder_linux_nofs.o
binder_linux_nofs-y := binder.o binder_alloc.o shim.o symbols.o
ccflags-y += -I$(src)/uapi -I$(src)
ccflags-y += -include $(src)/shim_rename.h
ccflags-y += -DCONFIG_ANDROID_BINDER_DEVICES='"binder,hwbinder,vndbinder"'
ccflags-y += -include $(src)/symbols.h
ccflags-y += -Wno-error=incompatible-pointer-types -Wno-incompatible-pointer-types

KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

.PHONY: all clean
