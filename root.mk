################################################################
# Root Makefile of the whole project
################################################################

# Basic Definitions
################################################################
ARCH		:= arm
ABI		:= eabi
BOARD		?= 96b_ivy5661
BOOT		:= mcuboot
KERNEL		:= zephyr
OS		:= $(KERNEL)

CROSS_COMPILE   := $(ARCH)-$(OS)-$(ABI)-

REPEATER	:= repeater
MP_TEST		:= mp_test

# Directories and Files
################################################################
SHELL		:= /bin/bash
PWD		:= $(shell pwd)
PRJDIR		:= $(PWD)

app_DIR		:= $(PRJDIR)/apps
boot_DIR	:= $(PRJDIR)/$(BOOT)
kernel_DIR	:= $(PRJDIR)/$(KERNEL)

BUILD_DIR		:= $(PRJDIR)/output
boot_BUILD_DIR		:= $(BUILD_DIR)/$(BOOT)
repeater_BUILD_DIR	:= $(BUILD_DIR)/$(REPEATER)
mp_test_BUILD_DIR	:= $(BUILD_DIR)/$(MP_TEST)

BOOT_BIN	:= $(boot_BUILD_DIR)/$(KERNEL)/$(KERNEL).bin
REPEATER_BIN	:= $(repeater_BUILD_DIR)/$(KERNEL)/$(KERNEL).bin
MP_TEST_BIN	:= $(mp_test_BUILD_DIR)/$(KERNEL)/$(KERNEL).bin

DIST_DIR	:= $(PRJDIR)/output/images
BOOT_DIST_BIN	:= $(DIST_DIR)/$(BOOT)-pubkey.bin
REPEATER_DIST_BIN	:= $(DIST_DIR)/$(REPEATER)-signed-ota.bin
MP_TEST_DIST_BIN	:= $(DIST_DIR)/$(MP_TEST)-signed-ota.bin

IMGTOOL = $(boot_DIR)/scripts/imgtool.py

# Macros
################################################################
# MESSAGE Macro -- display a message in bold type
MESSAGE = echo "\n$(TERM_BOLD)>>> $(1)$(TERM_RESET)"
TERM_BOLD := $(shell tput smso 2>/dev/null)
TERM_RESET := ${shell tput rmso 2>/dev/null}

# Macro of Building Targets
# $(1): Target
# $(2): Dir of main
define MAKE_TARGET
.PHONY: $(1)
$(1): 
	@ $(call MESSAGE,"Building $(1)")
	@ if [ ! -d $($(1)_BUILD_DIR) ]; then mkdir -p $($(1)_BUILD_DIR); fi
	(source $(kernel_DIR)/zephyr-env.sh && cd $($(1)_BUILD_DIR) && \
	if [ ! -f Makefile ] ; then cmake -DBOARD=$(BOARD) -DCONF_FILE=prj$(findstring _debug,$(1)).conf $(2); fi && \
	make \
	)
endef

# Macro of Cleaning Targets
# $(1): Target
# $(2): Target suffix
# $(3): .config
define CLEAN_TARGET
.PHONY: $(if $(2),$(1)-$(2),$(1))
$(if $(2),$(1)-$(2),$(1)):
	@ $(call MESSAGE,"Cleaning $(1)")
	@ if [ -d $($(1)_BUILD_DIR) ]; then make -C $($(1)_BUILD_DIR) $(2); fi
endef

SIGNING_KEY	?= $(boot_DIR)/root-rsa-2048.pem
BOOT_HEADER_LEN	:= 0x1000
FLASH_ALIGNMENT	:= 8

# Macro of Signing KERNEL Image
# $(1): input file
# $(2): output file
define SIGN_KERNEL_IMAGE
	@ $(IMGTOOL) sign \
		--key $(SIGNING_KEY) \
		--header-size $(BOOT_HEADER_LEN) \
		--align $(FLASH_ALIGNMENT) \
		--version 1.2 \
		--slot-size 0x60000 \
		$(1) $(2)
endef

# Targets
################################################################
DEFAULT_TARGETS		:= boot repeater mp_test
DIST_TARGETS		:= $(DEFAULT_TARGETS) 
ALL_TARGETS		:= $(DEFAULT_TARGETS)
CLEAN_TARGETS		:= $(addsuffix -clean,$(ALL_TARGETS))

uboot_DIR	:= $(PRJDIR)/u-boot
KEY_DIR		:= $(uboot_DIR)/rsa-keypair
KEY_NAME	:= dev
KEY_DTB		:= $(uboot_DIR)/u-boot-pubkey.dtb
ITB		:= $(uboot_DIR)/fit-$(BOARD).itb

FLASH_BASE		:= 0x02000000
KERNEL_PARTTION_OFFSET	:= 0x00040000
KERNEL_BOOT_ADDR	:= 0x$(shell printf "%08x" $(shell echo $$(( $(FLASH_BASE) + $(KERNEL_PARTTION_OFFSET) ))))
FIT_HEADER_SIZE		:= 0x1000
KERNEL_LOAD_ADDR	:= 0x$(shell printf "%08x" $(shell echo $$(( $(KERNEL_BOOT_ADDR) + $(FIT_HEADER_SIZE) ))))
KERNEL_ENTRY_ADDR	:= 0x$(shell printf "%08x" $(shell echo $$(( $(KERNEL_LOAD_ADDR) + 0x4 ))))

# Macro of Signing OS Image
# $(1): Compression type
# $(2): Load address
# $(3): Entry point
# $(4): Key dir
# $(5): Key name
define SIGN_OS_IMAGE
	ITS=$(uboot_DIR)/fit-$(BOARD).its; \
	cp -f $(uboot_DIR)/dts/dt.dtb $(KEY_DTB); \
	$(uboot_DIR)/scripts/mkits.sh \
		-D $(BOARD) -o $$ITS -k $(6) -C $(1) -a $(2) -e $(3) -A $(ARCH) -K $(KERNEL) $(if $(5),-s $(5)); \
	PATH=$(uboot_DIR)/tools:$(uboot_DIR)/scripts/dtc:$(PATH) mkimage -f $$ITS -K $(KEY_DTB) $(if $(4),-k $(4)) -r -E -p $(FIT_HEADER_SIZE) $(ITB)
endef

.PHONY: dist
dist: $(DIST_TARGETS)
	@ if [ ! -d $(DIST_DIR) ]; then install -d $(DIST_DIR); fi
	@ install $(BOOT_BIN) $(BOOT_DIST_BIN)
	$(call SIGN_KERNEL_IMAGE,$(REPEATER_BIN),$(REPEATER_DIST_BIN))
	$(call SIGN_KERNEL_IMAGE,$(MP_TEST_BIN),$(MP_TEST_DIST_BIN))
#	building u-boot temporarily
	if [ ! -f $(DIST_DIR)/u-boot-pubkey-dtb.bin ]; then \
	source $(kernel_DIR)/zephyr-env.sh && $(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(uboot_DIR) distclean; \
	sed -i 's/bootm 0x......../bootm $(KERNEL_BOOT_ADDR)/' $(uboot_DIR)/include/configs/uwp566x_evb.h; \
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(uboot_DIR) uwp566x_evb_defconfig; \
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(uboot_DIR); \
	fi
#	sign kernel for u-boot loading
	@ mv $(REPEATER_BIN) $(REPEATER_BIN).orig
	@ dd if=$(REPEATER_BIN).orig of=$(REPEATER_BIN) bs=4K skip=1
	$(call SIGN_OS_IMAGE,none,$(KERNEL_LOAD_ADDR),$(KERNEL_ENTRY_ADDR),$(KEY_DIR),$(KEY_NAME),$(REPEATER_BIN))
	source $(kernel_DIR)/zephyr-env.sh && $(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(uboot_DIR) EXT_DTB=$(KEY_DTB)
	@ mv $(REPEATER_BIN).orig $(REPEATER_BIN)
	install $(ITB) $(REPEATER_DIST_BIN)
#	sign kernel for u-boot loading
	@ mv $(MP_TEST_BIN) $(MP_TEST_BIN).orig
	@ dd if=$(MP_TEST_BIN).orig of=$(MP_TEST_BIN) bs=4K skip=1
	$(call SIGN_OS_IMAGE,none,$(KERNEL_LOAD_ADDR),$(KERNEL_ENTRY_ADDR),$(KEY_DIR),$(KEY_NAME),$(MP_TEST_BIN))
	source $(kernel_DIR)/zephyr-env.sh && $(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(uboot_DIR) EXT_DTB=$(KEY_DTB)
	@ mv $(MP_TEST_BIN).orig $(MP_TEST_BIN)
	install $(ITB) $(MP_TEST_DIST_BIN)
	install $(uboot_DIR)/u-boot.bin $(DIST_DIR)/u-boot-pubkey-dtb.bin;
	install $(DIST_DIR)/u-boot-pubkey-dtb.bin $(DIST_DIR)/mcuboot-pubkey.bin;

.PHONY: clean
clean: $(CLEAN_TARGETS)

.PHONY: distclean
distclean:
	@ if [ -d $(BUILD_DIR) ]; then rm -rf $(BUILD_DIR); fi

# Respective Targets
################################################################

# Build Targets
$(eval $(call MAKE_TARGET,boot,$(boot_DIR)/boot/zephyr))

$(eval $(call MAKE_TARGET,repeater,$(app_DIR)/repeater))

$(eval $(call MAKE_TARGET,mp_test,$(app_DIR)/mp_test))

# Clean Targets
$(foreach target,$(ALL_TARGETS),$(eval $(call CLEAN_TARGET,$(target),clean)))
