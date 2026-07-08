# ==============================================================================
# project.mk — User project configuration
# Edit this file; never edit the generated Makefile.mk files.
# ==============================================================================

# Output artefact name (binary, library, or simulation target)
PROJECT_NAME := cdc_lib

# Build output directory
BUILD_DIR := build

# Toolchain selection — uncomment exactly one:
#   gcc       GNU C Compiler          (.c)
#   gxx       GNU C++ Compiler        (.cpp .cxx .cc)
#   ghdl      GHDL VHDL simulator     (.vhd .vhdl)
#   modelsim  ModelSim / QuestaSim    (.vhd .vhdl .v .sv)
#   vivado    Xilinx Vivado           (.vhd .v .sv .xdc)
#   quartus   Intel/Altera Quartus    (.vhd .v .sv .qsf)
TOOLCHAIN := ghdl

# Directory where the scan script starts (default: project root ".")
SRC_ROOT := .

# ── VHDL_SRCS_DIR: directory-level compilation order (Layer 1) ───────────────
# VHDL compilation order matters: packages must precede their users, entities
# must precede their instantiators.  Three layers handle this:
#
#   Layer 3 (automatic): ghdl.mk / modelsim.mk run a silent pre-pass that
#     pre-populates the work library.  Handles most designs with zero effort.
#
#   Layer 2 (semi-automatic): 'make scan' creates a per-directory .compile_order
#     listing files alphabetically as a starting point.  Edit it once to set the
#     correct within-directory order.  Never overwritten by subsequent scans.
#
#   Layer 1 (this variable): controls cross-directory order when Layers 2+3
#     are not enough.  List directories in compilation order — file discovery
#     within each directory is still fully automatic (via its .compile_order or
#     $(wildcard)).  All VHDL directories must be listed when this is set.
#
# src (package + entities) must be compiled before tb (instantiates them):
VHDL_SRCS_DIR := \
    src          \
    tb

# ── GNU C / C++ settings ──────────────────────────────────────────────────────
CC       := gcc
CXX      := g++
AR       := ar
CFLAGS   := -Wall -Wextra -O2 -g
CXXFLAGS := -Wall -Wextra -O2 -g -std=c++17
LDFLAGS  :=
LIBS     :=
# Space-separated list of extra include directories
INC_DIRS :=

# ── GHDL settings ─────────────────────────────────────────────────────────────
# Comments on their own line: trailing spaces before an inline comment are
# kept by ':=' and end up inside the value.
GHDL       := ghdl
# VHDL standard: 87 | 93 | 00 | 02 | 08
GHDL_STD   := 93
GHDL_FLAGS :=
# Top-level entity for elaboration/simulation
GHDL_TOP   := tb_cdc_lib
# Extra flags passed to the simulation step
GHDL_SIM_FLAGS :=

# ── ModelSim / QuestaSim settings ─────────────────────────────────────────────
VLIB      := vlib
VMAP      := vmap
VCOM      := vcom
VLOG      := vlog
VSIM      := vsim
VSIM_WORK := work
VSIM_TOP  := top
VSIM_FLAGS :=

# ── Xilinx Vivado settings ────────────────────────────────────────────────────
VIVADO      := vivado
VIVADO_PART := xc7a35tcpg236-1   # Target device part number
VIVADO_TOP  := top                # Top-level design unit
VIVADO_XDC  :=                    # Constraints file(s), space-separated

# ── Intel/Altera Quartus Prime settings ───────────────────────────────────────
QUARTUS_SH   := quartus_sh
QUARTUS_MAP  := quartus_map
QUARTUS_FIT  := quartus_fit
QUARTUS_ASM  := quartus_asm
QUARTUS_STA  := quartus_sta
QUARTUS_PART := EP4CE6E22C8       # Target device
QUARTUS_TOP  := top               # Top-level entity
QUARTUS_FAMILY := "Cyclone IV E"
