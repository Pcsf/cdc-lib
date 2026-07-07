--------------------------------------------------------------------------------
-- dpram.vhd
--
-- Dual-clock simple dual-port RAM: port A writes (clk_a), port B reads
-- (clk_b, synchronous read, 1-cycle latency; 2 cycles with G_OUTPUT_REG).
-- Maps to block RAM on Xilinx and Intel devices.
--
-- The RAM itself performs no synchronization: it is safe only when the
-- surrounding control logic guarantees that a location is never read while
-- it is being written (e.g. gray-coded pointers as in cdc_async_fifo, or a
-- handshake/bank-switch scheme). Simultaneous write/read of the same address
-- from the two clock domains returns undefined data.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram is
  generic (
    G_DATA_WIDTH : positive := 8;
    G_ADDR_WIDTH : positive := 4;      -- depth = 2**G_ADDR_WIDTH
    G_OUTPUT_REG : boolean  := false   -- extra output register on port B
  );
  port (
    -- port A: write
    clk_a  : in  std_logic;
    en_a   : in  std_logic := '1';
    we_a   : in  std_logic;
    addr_a : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    din_a  : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    -- port B: read
    clk_b  : in  std_logic;
    en_b   : in  std_logic := '1';
    addr_b : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    dout_b : out std_logic_vector(G_DATA_WIDTH - 1 downto 0)
  );
end entity dpram;

architecture rtl of dpram is

  constant C_DEPTH : natural := 2 ** G_ADDR_WIDTH;

  type t_ram is array (0 to C_DEPTH - 1)
    of std_logic_vector(G_DATA_WIDTH - 1 downto 0);

  signal ram      : t_ram := (others => (others => '0'));
  signal dout_int : std_logic_vector(G_DATA_WIDTH - 1 downto 0) := (others => '0');

begin

  p_write : process (clk_a)
  begin
    if rising_edge(clk_a) then
      if en_a = '1' and we_a = '1' then
        ram(to_integer(unsigned(addr_a))) <= din_a;
      end if;
    end if;
  end process;

  p_read : process (clk_b)
  begin
    if rising_edge(clk_b) then
      if en_b = '1' then
        dout_int <= ram(to_integer(unsigned(addr_b)));
      end if;
    end if;
  end process;

  gen_oreg : if G_OUTPUT_REG generate
    p_oreg : process (clk_b)
    begin
      if rising_edge(clk_b) then
        if en_b = '1' then
          dout_b <= dout_int;
        end if;
      end if;
    end process;
  end generate;

  gen_noreg : if not G_OUTPUT_REG generate
    dout_b <= dout_int;
  end generate;

end architecture rtl;
