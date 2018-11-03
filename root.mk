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

PROFILE		?= repeater

# Directories and Files
################################################################
SHELL		:= /bin/bash
PWD		:= $(shell pwd)
PRJDIR		:= $(PWD)

app_DIR		:= $(PRJDIR)/apps
profile_DIR	:= $(app_DIR)/$(PROFILE)
boot_DIR	:= $(PRJDIR)/$(BOOT)
kernel_DIR	:= $(PRJDIR)/$(KERNEL)
dloader_DIR	:= $(PRJDIR)/dloader
fw_DIR		:= $(PRJDIR)/firmware

BUILD_DIR		:= $(PRJDIR)/output
boot_BUILD_DIR		:= $(BUILD_DIR)/$(BOOT)
kernel_BUILD_DIR	:= $(BUILD_DIR)/$(PROFILE)

BOOT_BIN	:= $(boot_BUILD_DIR)/$(KERNEL)/$(KERNEL).bin
KERNEL_BIN	:= $(kernel_BUILD_DIR)/$(KERNEL)/$(KERNEL).bin
DLOADER_BIN	:= $(dloader_DIR)/dloader

DIST_DIR	:= $(kernel_BUILD_DIR)/images
BOOT_DIST_BIN	:= $(DIST_DIR)/$(BOOT)-pubkey.bin
KERNEL_DIST_BIN	:= $(DIST_DIR)/$(KERNEL)-signed-ota.bin
DLOADER_DIST_BIN:= $(BUILD_DIR)/dloader/dloader

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
DEFAULT_TARGETS		:= boot kernel
DIST_TARGETS		:= $(DEFAULT_TARGETS) dloader
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
	$(call SIGN_KERNEL_IMAGE,$(KERNEL_BIN),$(KERNEL_DIST_BIN))
#	building u-boot temporarily
	@ if [ ! -f $(DIST_DIR)/u-boot-pubkey-dtb.bin ]; then \
	source $(kernel_DIR)/zephyr-env.sh && $(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(uboot_DIR) distclean; \
	sed -i 's/bootm 0x......../bootm $(KERNEL_BOOT_ADDR)/' $(uboot_DIR)/include/configs/uwp566x_evb.h; \
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(uboot_DIR) uwp566x_evb_defconfig; \
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(uboot_DIR); \
	fi
#	sign kernel for u-boot loading
	@ mv $(KERNEL_BIN) $(KERNEL_BIN).orig
	@ dd if=$(KERNEL_BIN).orig of=$(KERNEL_BIN) bs=4K skip=1
	$(call SIGN_OS_IMAGE,none,$(KERNEL_LOAD_ADDR),$(KERNEL_ENTRY_ADDR),$(KEY_DIR),$(KEY_NAME),$(KERNEL_BIN))
	source $(kernel_DIR)/zephyr-env.sh && $(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(uboot_DIR) EXT_DTB=$(KEY_DTB)
	@ mv $(KERNEL_BIN).orig $(KERNEL_BIN)
	install $(ITB) $(DIST_DIR)/zephyr-signed-ota.bin
	@ install $(uboot_DIR)/u-boot.bin $(DIST_DIR)/u-boot-pubkey-dtb.bin;
	@ install $(DIST_DIR)/u-boot-pubkey-dtb.bin $(DIST_DIR)/mcuboot-pubkey.bin;
	@ install -d $(BUILD_DIR)/dloader
	@ install $(DLOADER_BIN) $(DLOADER_DIST_BIN)
	@ cp $(dloader_DIR)/ini/* $(BUILD_DIR)/dloader
	@ install -m 775 build/update_fw.sh $(DIST_DIR)
	@ install build/flash_patition.xml $(DIST_DIR)
	@ install $(fw_DIR)/unsc_marlin3_mcu_ZEPHYR.pac $(DIST_DIR)

.PHONY: clean
clean: $(CLEAN_TARGETS)

.PHONY: distclean
distclean:
	@ if [ -d $(BUILD_DIR) ]; then rm -rf $(BUILD_DIR); fi

# Respective Targets
################################################################

# Build Targets
$(eval $(call MAKE_TARGET,boot,$(boot_DIR)/boot/zephyr))

$(eval $(call MAKE_TARGET,kernel,$(profile_DIR)))

$(DLOADER_DIST_BIN):
	@ $(call MESSAGE,"Building dloader")
	$(MAKE) -C $(dloader_DIR)

.PHONY: dloader
dloader: $(DLOADER_DIST_BIN)

# Clean Targets
$(foreach target,$(ALL_TARGETS),$(eval $(call CLEAN_TARGET,$(target),clean)))
