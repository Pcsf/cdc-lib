--------------------------------------------------------------------------------
-- cdc_pkg.vhd
--
-- Clock Domain Crossing (CDC) library package.
-- Component declarations and gray-code helper functions.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package cdc_pkg is

  -- Binary to gray code conversion
  function bin2gray (b : unsigned) return unsigned;

  -- Gray code to binary conversion
  function gray2bin (g : unsigned) return unsigned;

  ------------------------------------------------------------------------------
  -- Single-bit level synchronizer (N-flop)
  ------------------------------------------------------------------------------
  component cdc_sync_bit is
    generic (
      G_STAGES    : positive  := 2;
      G_RESET_VAL : std_logic := '0'
    );
    port (
      clk_dst : in  std_logic;
      rst_dst : in  std_logic;
      din     : in  std_logic;
      dout    : out std_logic
    );
  end component;

  ------------------------------------------------------------------------------
  -- Pulse synchronizer (toggle scheme), active level selectable
  ------------------------------------------------------------------------------
  component cdc_sync_pulse is
    generic (
      G_STAGES       : positive  := 2;
      G_ACTIVE_LEVEL : std_logic := '1'
    );
    port (
      clk_src   : in  std_logic;
      rst_src   : in  std_logic;
      pulse_src : in  std_logic;
      busy      : out std_logic;
      clk_dst   : in  std_logic;
      rst_dst   : in  std_logic;
      pulse_dst : out std_logic
    );
  end component;

  ------------------------------------------------------------------------------
  -- Multi-bit data crossing with req/ack (toggle) handshake
  ------------------------------------------------------------------------------
  component cdc_handshake is
    generic (
      G_WIDTH  : positive := 8;
      G_STAGES : positive := 2
    );
    port (
      clk_src   : in  std_logic;
      rst_src   : in  std_logic;
      valid_src : in  std_logic;
      ready_src : out std_logic;
      data_src  : in  std_logic_vector(G_WIDTH - 1 downto 0);
      clk_dst   : in  std_logic;
      rst_dst   : in  std_logic;
      valid_dst : out std_logic;
      data_dst  : out std_logic_vector(G_WIDTH - 1 downto 0)
    );
  end component;

  ------------------------------------------------------------------------------
  -- Dual-clock simple dual-port RAM (write port A, read port B)
  ------------------------------------------------------------------------------
  component dpram is
    generic (
      G_DATA_WIDTH : positive := 8;
      G_ADDR_WIDTH : positive := 4;
      G_OUTPUT_REG : boolean  := false
    );
    port (
      clk_a  : in  std_logic;
      en_a   : in  std_logic := '1';
      we_a   : in  std_logic;
      addr_a : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
      din_a  : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
      clk_b  : in  std_logic;
      en_b   : in  std_logic := '1';
      addr_b : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
      dout_b : out std_logic_vector(G_DATA_WIDTH - 1 downto 0)
    );
  end component;

  ------------------------------------------------------------------------------
  -- Ping-pong (double-bank) buffer for random-access block transfers
  ------------------------------------------------------------------------------
  component cdc_pingpong is
    generic (
      G_DATA_WIDTH : positive := 8;
      G_ADDR_WIDTH : positive := 4;
      G_STAGES     : positive := 2;
      G_OUTPUT_REG : boolean  := false
    );
    port (
      clk_wr   : in  std_logic;
      rst_wr   : in  std_logic;
      wr_ready : out std_logic;
      wr_en    : in  std_logic;
      wr_addr  : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
      wr_data  : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
      wr_commit : in  std_logic;
      clk_rd   : in  std_logic;
      rst_rd   : in  std_logic;
      rd_valid : out std_logic;
      rd_addr  : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
      rd_data  : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
      rd_release : in  std_logic
    );
  end component;

  ------------------------------------------------------------------------------
  -- Asynchronous FIFO with gray-coded pointers (depth = 2**G_ADDR_WIDTH)
  ------------------------------------------------------------------------------
  component cdc_async_fifo is
    generic (
      G_DATA_WIDTH : positive := 8;
      G_ADDR_WIDTH : positive := 4;
      G_STAGES     : positive := 2
    );
    port (
      clk_wr   : in  std_logic;
      rst_wr   : in  std_logic;
      wr_en    : in  std_logic;
      wr_data  : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
      full     : out std_logic;
      clk_rd   : in  std_logic;
      rst_rd   : in  std_logic;
      rd_en    : in  std_logic;
      rd_data  : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
      rd_valid : out std_logic;
      empty    : out std_logic
    );
  end component;

end package cdc_pkg;

package body cdc_pkg is

  function bin2gray (b : unsigned) return unsigned is
  begin
    return b xor shift_right(b, 1);
  end function;

  function gray2bin (g : unsigned) return unsigned is
    variable ga : unsigned(g'length - 1 downto 0) := g;
    variable b  : unsigned(g'length - 1 downto 0);
  begin
    b(b'high) := ga(ga'high);
    for i in b'high - 1 downto 0 loop
      b(i) := b(i + 1) xor ga(i);
    end loop;
    return b;
  end function;

end package body cdc_pkg;
