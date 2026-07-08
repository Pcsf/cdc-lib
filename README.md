# cdc-lib — VHDL Clock Domain Crossing Library

Vendor-neutral, synthesizable CDC synchronizers written in VHDL-93 (compatible
with any later standard). Verified with GHDL; includes synthesis attributes
for Xilinx (Vivado) and Intel/Altera (Quartus).

## Components

| Component        | Use case                                                        |
|------------------|-----------------------------------------------------------------|
| `cdc_sync_bit`   | Single-bit level signal (N-flop synchronizer, default 2)        |
| `cdc_sync_pulse` | Single-cycle pulse, active high or active low (toggle scheme)   |
| `cdc_handshake`  | Multi-bit data, low rate (req/ack toggle handshake)             |
| `cdc_async_fifo` | Multi-bit data, streaming (gray-coded pointer dual-clock FIFO)  |
| `cdc_pingpong`   | Multi-bit data, random-access blocks (double-bank buffer)       |
| `dpram`          | Multi-bit data, shared buffer (dual-clock simple dual-port RAM) |

All component declarations plus `bin2gray`/`gray2bin` helper functions are in
`cdc_pkg` (`use work.cdc_pkg.all;`).

## Usage notes

### cdc_sync_bit
- Input must come from a register in the source domain (no combinational
  glitches) and stay stable for more than one destination clock period.
- Never synchronize the bits of a bus this way unless the bits are independent
  or the bus is gray-coded — bits would skew against each other.
- `G_STAGES >= 2`; use 3 for very high destination clock frequencies.

### cdc_sync_pulse
- `G_ACTIVE_LEVEL = '1'`: idle low, one-cycle high pulse in and out.
  `G_ACTIVE_LEVEL = '0'`: idle high, one-cycle low pulse in and out.
- Every accepted source pulse produces exactly one destination pulse.
- `busy` (source domain, active high) covers the full round trip; pulses
  arriving while `busy = '1'` are **ignored** — check `busy` before pulsing.

### cdc_handshake
- Source: word accepted when `valid_src = '1'` and `ready_src = '1'` on a
  `clk_src` edge. `ready_src` stays low until the destination acknowledged.
- Destination: `valid_dst` pulses one `clk_dst` cycle; `data_dst` holds until
  the next word.
- Throughput ≈ one word per synchronizer round trip. For sustained streams
  use `cdc_async_fifo`.

### cdc_async_fifo
- First-word fall-through (show-ahead) read interface: whenever `empty = '0'`
  (equivalently `rd_valid = '1'`) the oldest word is already on `rd_data`;
  `rd_en = '1'` pops it and the next word appears the following cycle. This
  maps 1:1 onto valid/ready streaming interfaces (e.g. AXI-Stream:
  `tvalid = rd_valid`, `rd_en = tvalid and tready`).
- Write when `full = '0'`; writes while full are ignored. Sustains one word
  per clock on both sides; the internal prefetch stage keeps the storage
  BRAM-friendly. Capacity = `2**G_ADDR_WIDTH + 1` words.
- `full`/`empty` are pessimistic (may deassert a few cycles late) but never
  allow overflow/underflow, data loss, or duplication.

### cdc_pingpong
- Double-bank (ping-pong) buffer for block transfers where the consumer needs
  random access (frames, lines, packets, sample blocks). Per-bank depth =
  `2**G_ADDR_WIDTH`; storage is one `dpram` with the bank select as address MSB.
- Writer: while `wr_ready = '1'` fill the current bank in any order via
  `wr_en`/`wr_addr`/`wr_data`, then pulse `wr_commit` for one cycle to hand it
  to the reader. `wr_ready` never drops mid-fill (only `wr_commit` clears it);
  writes and commits while `wr_ready = '0'` are ignored.
- Reader: while `rd_valid = '1'` the committed bank is on the read port;
  `rd_data` returns the word at `rd_addr` after 1 `clk_rd` cycle (2 with
  `G_OUTPUT_REG`). Pulse `rd_release` for one cycle to return the bank.
- Port names avoid the bare word `release`, which is reserved in VHDL-2008.
- Both banks can be outstanding at once, so the writer fills bank 1 while the
  reader consumes bank 0 (full double buffering). Bank ownership uses 2-bit
  gray-coded pointers, the same scheme as the FIFO.

### dpram
- Deliberately named without the `cdc_` prefix: it is a plain dual-clock
  memory primitive, not a synchronizer.
- Write on port A (`clk_a`), synchronous read on port B (`clk_b`); optional
  extra output register (`G_OUTPUT_REG`) for block-RAM output pipelining.
- Performs **no synchronization by itself**: surrounding logic must guarantee
  a location is not read while being written (gray-coded pointers, handshake,
  or bank switching). Used internally by `cdc_async_fifo`.

### Entity name collisions
`dpram` is a generic name; a larger project may already have an entity called
`dpram` compiled into `work`. If so, compile cdc-lib into its own named
library instead of renaming anything — the internal `entity work.…`
references still resolve correctly, because `work` always denotes the library
a file is being compiled into:

```sh
# GHDL
ghdl -a --work=cdc_lib src/*.vhd
```

```tcl
# Vivado
set_property LIBRARY cdc_lib [get_files {src/*.vhd}]
```

```tcl
# Quartus (.qsf)
set_global_assignment -name VHDL_FILE src/dpram.vhd -library cdc_lib
# ... same -library for the other files
```

Then reference the components through the library name:

```vhdl
library cdc_lib;
use cdc_lib.cdc_pkg.all;
...
u_fifo : entity cdc_lib.cdc_async_fifo generic map (...) port map (...);
```

### Resets
All resets are synchronous, active high, and per-domain. Components with two
domains assume both resets assert/release together (overlapping reset); do not
operate one side while the other is still in reset.

## Timing constraints

The synchronizer flops carry `ASYNC_REG`/`shreg_extract` (Xilinx) and
`SYNCHRONIZER_IDENTIFICATION` (Intel) attributes. You still need to relax the
crossing paths in your constraints, e.g. for Vivado (XDC):

```tcl
# all paths into the synchronizer chains
set_max_delay -datapath_only -from [get_clocks clk_src] \
    -to [get_pins -hier -filter {NAME =~ */sync_regs_reg[0]/D}] [get_property PERIOD [get_clocks clk_dst]]

# cdc_handshake data bus (stable when sampled, protected by the handshake)
set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ */data_reg_reg[*]}] \
    -to [get_cells -hier -filter {NAME =~ */data_dst_reg[*]}] [get_property PERIOD [get_clocks clk_dst]]
```

or globally, if the two clocks are truly independent:

```tcl
set_clock_groups -asynchronous -group [get_clocks clk_src] -group [get_clocks clk_dst]
```

Quartus (SDC) equivalent: `set_clock_groups -asynchronous ...` or
`set_max_delay`/`set_net_delay` on the same paths.

## Simulation

Self-checking testbench covering all components with two unrelated clocks:

```sh
git submodule update --init   # once, after cloning
make            # scan (first run), analyze, elaborate, simulate; VCD in build/
```

The build system is the [makefile_project_template](https://github.com/Pcsf/makefile_project_template)
submodule (checked out at `mk/`), driven by the one-line root `Makefile` and
configured in `project.mk` (`TOOLCHAIN := ghdl`, `GHDL_TOP := tb_cdc_lib`).
Compilation order lives in `src/.compile_order` and `tb/.compile_order`;
`make help` lists all targets. Update the build system with
`git -C mk pull`. Or run GHDL manually:

```sh
mkdir -p build
ghdl -a --std=93 --workdir=build src/*.vhd tb/tb_cdc_lib.vhd
ghdl -e --std=93 --workdir=build tb_cdc_lib
ghdl -r --std=93 --workdir=build tb_cdc_lib
```

Expected output ends with `ALL TESTS PASSED`.

## File list

```
src/cdc_pkg.vhd         package: components + gray-code functions
src/cdc_sync_bit.vhd    N-flop single-bit synchronizer
src/cdc_sync_pulse.vhd  pulse synchronizer (active high/low)
src/cdc_handshake.vhd   multi-bit req/ack handshake
src/dpram.vhd           dual-clock simple dual-port RAM
src/cdc_async_fifo.vhd  gray-pointer asynchronous FIFO
src/cdc_pingpong.vhd    double-bank (ping-pong) block buffer
tb/tb_cdc_lib.vhd       self-checking testbench
```

Compile order: `cdc_pkg` → `cdc_sync_bit` → `dpram` → remaining files.
