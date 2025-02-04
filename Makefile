
RISCV_GNU_TOOLCHAIN_GIT_REVISION = 411d134
RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX = /opt/riscv32

# Give the user some easy overrides for local configuration quirks.
# If you change one of these and it breaks, then you get to keep both pieces.
SHELL = bash
PYTHON = python3
VERILATOR = verilator
ICARUS_SUFFIX =
IVERILOG = iverilog$(ICARUS_SUFFIX)
VVP = vvp$(ICARUS_SUFFIX)

TEST_OBJS = $(addsuffix .o,$(basename $(wildcard tests/*.S)))
FIRMWARE_OBJS = firmware/start.o firmware/irq.o firmware/print.o firmware/hello.o firmware/sieve.o firmware/multest.o firmware/stats.o
GCC_WARNS  = -Werror -Wall -Wextra -Wshadow -Wundef -Wpointer-arith -Wcast-qual -Wcast-align -Wwrite-strings
GCC_WARNS += -Wredundant-decls -Wstrict-prototypes -Wmissing-prototypes -pedantic # -Wconversion
TOOLCHAIN_PREFIX = $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX)i/bin/riscv32-unknown-elf-
COMPRESSED_ISA = C

# Add things like "export http_proxy=... https_proxy=..." here
GIT_ENV = true

#VCS Simulator options
VCS = vcs
VCS_FLAGS = -full64 -debug_all +v2k

simv: testbench.v picorv32.v
	 $(VCS) $(VCS_FLAGS) $(RISCV_FORMAL_DEFINE) -o $@ $(subst C,-DCOMPRESSED_ISA,$(COMPRESSED_ISA)) $^
.PHONY: simv

test: simv firmware/firmware.hex
	./simv 
 
test_vcd: simv firmware/firmware.hex
	./simv +vcd 

test_rvf: simv firmware/firmware.hex
	./simv +vcd +trace +noerror

test_axi: simv firmware/firmware.hex
	./simv +axi_test

check: check-yices

check-%: check.smt2
	yosys-smtbmc -s $(subst check-,,$@) -t 30 --dump-vcd check.vcd check.smt2
	yosys-smtbmc -s $(subst check-,,$@) -t 25 --dump-vcd check.vcd -i check.smt2

check.smt2: picorv32.v
	yosys -v2 -p 'read_verilog -formal picorv32.v' \
	          -p 'prep -top picorv32 -nordff' \
		  -p 'assertpmux -noinit; opt -fast; dffunmap' \
		  -p 'write_smt2 -wires check.smt2'

synth.v: picorv32.v scripts/yosys/synth_sim.ys
	yosys -qv3 -l synth.log scripts/yosys/synth_sim.ys

firmware/firmware.hex: firmware/firmware.bin firmware/makehex.py
	$(PYTHON) firmware/makehex.py $< 32768 > $@

firmware/firmware.bin: firmware/firmware.elf
	$(TOOLCHAIN_PREFIX)objcopy -O binary $< $@
	chmod -x $@

firmware/firmware.elf: $(FIRMWARE_OBJS) $(TEST_OBJS) firmware/sections.lds
	$(TOOLCHAIN_PREFIX)gcc -Os -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -ffreestanding -nostdlib -o $@ \
		-Wl,--build-id=none,-Bstatic,-T,firmware/sections.lds,-Map,firmware/firmware.map,--strip-debug \
		$(FIRMWARE_OBJS) $(TEST_OBJS) -lgcc
	chmod -x $@

firmware/start.o: firmware/start.S
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -o $@ $<

firmware/%.o: firmware/%.c
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32i$(subst C,c,$(COMPRESSED_ISA)) -Os --std=c99 $(GCC_WARNS) -ffreestanding -nostdlib -o $@ $<

tests/%.o: tests/%.S tests/riscv_test.h tests/test_macros.h
	$(TOOLCHAIN_PREFIX)gcc -c -mabi=ilp32 -march=rv32im -o $@ -DTEST_FUNC_NAME=$(notdir $(basename $<)) \
		-DTEST_FUNC_TXT='"$(notdir $(basename $<))"' -DTEST_FUNC_RET=$(notdir $(basename $<))_ret $<

download-tools:
	sudo bash -c 'set -ex; mkdir -p /var/cache/distfiles; $(GIT_ENV); \
	$(foreach REPO,riscv-gnu-toolchain riscv-binutils-gdb riscv-gcc riscv-glibc riscv-newlib, \
		if ! test -d /var/cache/distfiles/$(REPO).git; then rm -rf /var/cache/distfiles/$(REPO).git.part; \
			git clone --bare https://github.com/riscv/$(REPO) /var/cache/distfiles/$(REPO).git.part; \
			mv /var/cache/distfiles/$(REPO).git.part /var/cache/distfiles/$(REPO).git; else \
			(cd /var/cache/distfiles/$(REPO).git; git fetch https://github.com/riscv/$(REPO)); fi;)'

define build_tools_template
build-$(1)-tools:
	@read -p "This will remove all existing data from $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX)$(subst riscv32,,$(1)). Type YES to continue: " reply && [[ "$$$$reply" == [Yy][Ee][Ss] || "$$$$reply" == [Yy] ]]
	sudo bash -c "set -ex; rm -rf $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX)$(subst riscv32,,$(1)); mkdir -p $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX)$(subst riscv32,,$(1)); chown $$$${USER}: $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX)$(subst riscv32,,$(1))"
	+$(MAKE) build-$(1)-tools-bh

build-$(1)-tools-bh:
	+set -ex; $(GIT_ENV); \
	if [ -d /var/cache/distfiles/riscv-gnu-toolchain.git ]; then reference_riscv_gnu_toolchain="--reference /var/cache/distfiles/riscv-gnu-toolchain.git"; else reference_riscv_gnu_toolchain=""; fi; \
	if [ -d /var/cache/distfiles/riscv-binutils-gdb.git ]; then reference_riscv_binutils_gdb="--reference /var/cache/distfiles/riscv-binutils-gdb.git"; else reference_riscv_binutils_gdb=""; fi; \
	if [ -d /var/cache/distfiles/riscv-gcc.git ]; then reference_riscv_gcc="--reference /var/cache/distfiles/riscv-gcc.git"; else reference_riscv_gcc=""; fi; \
	if [ -d /var/cache/distfiles/riscv-glibc.git ]; then reference_riscv_glibc="--reference /var/cache/distfiles/riscv-glibc.git"; else reference_riscv_glibc=""; fi; \
	if [ -d /var/cache/distfiles/riscv-newlib.git ]; then reference_riscv_newlib="--reference /var/cache/distfiles/riscv-newlib.git"; else reference_riscv_newlib=""; fi; \
	rm -rf riscv-gnu-toolchain-$(1); git clone $$$$reference_riscv_gnu_toolchain https://github.com/riscv/riscv-gnu-toolchain riscv-gnu-toolchain-$(1); \
	cd riscv-gnu-toolchain-$(1); git checkout $(RISCV_GNU_TOOLCHAIN_GIT_REVISION); \
	git submodule update --init $$$$reference_riscv_binutils_gdb riscv-binutils; \
	git submodule update --init $$$$reference_riscv_binutils_gdb riscv-gdb; \
	git submodule update --init $$$$reference_riscv_gcc riscv-gcc; \
	git submodule update --init $$$$reference_riscv_glibc riscv-glibc; \
	git submodule update --init $$$$reference_riscv_newlib riscv-newlib; \
	mkdir build; cd build; ../configure --with-arch=$(2) --prefix=$(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX)$(subst riscv32,,$(1)); make

.PHONY: build-$(1)-tools
endef

$(eval $(call build_tools_template,riscv32i,rv32i))
$(eval $(call build_tools_template,riscv32ic,rv32ic))
$(eval $(call build_tools_template,riscv32im,rv32im))
$(eval $(call build_tools_template,riscv32imc,rv32imc))

build-tools:
	@echo "This will remove all existing data from $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX)i, $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX)ic, $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX)im, and $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX)imc."
	@read -p "Type YES to continue: " reply && [[ "$$reply" == [Yy][Ee][Ss] || "$$reply" == [Yy] ]]
	sudo bash -c "set -ex; rm -rf $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX){i,ic,im,imc}; mkdir -p $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX){i,ic,im,imc}; chown $${USER}: $(RISCV_GNU_TOOLCHAIN_INSTALL_PREFIX){i,ic,im,imc}"
	+$(MAKE) build-riscv32i-tools-bh
	+$(MAKE) build-riscv32ic-tools-bh
	+$(MAKE) build-riscv32im-tools-bh
	+$(MAKE) build-riscv32imc-tools-bh

toc:
	gawk '/^-+$$/ { y=tolower(x); gsub("[^a-z0-9]+", "-", y); gsub("-$$", "", y); printf("- [%s](#%s)\n", x, y); } { x=$$0; }' README.md

clean:
	rm -rf simv simv.daidir csrc *.vpd *.vcd ucli.key
 
.PHONY: clean
