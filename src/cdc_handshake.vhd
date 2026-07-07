--------------------------------------------------------------------------------
-- cdc_handshake.vhd
--
-- Multi-bit data crossing using a req/ack (2-phase toggle) handshake.
--
-- Source side: a word is accepted on the clk_src edge where valid_src = '1'
-- and ready_src = '1'. The data is held stable in a source-domain register
-- while a request toggle crosses to the destination; ready_src stays low
-- until the acknowledge toggle returns (full round trip).
--
-- Destination side: valid_dst pulses high for one clk_dst cycle with the new
-- word stable on data_dst (data_dst holds its value until the next word).
--
-- Throughput is one word per round trip (~ 2*G_STAGES + 2 cycles of each
-- clock); use cdc_async_fifo when sustained throughput is needed.
--
-- Constraints: the data_reg -> data_dst bus crosses domains directly. It is
-- guaranteed stable when sampled (protected by the handshake), so constrain
-- it with set_false_path or, better, set_max_delay -datapath_only.
--
-- Both resets are assumed to be asserted/released together (overlapping).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity cdc_handshake is
  generic (
    G_WIDTH  : positive := 8;  -- data width
    G_STAGES : positive := 2   -- synchronizer stages per crossing
  );
  port (
    -- source domain
    clk_src   : in  std_logic;
    rst_src   : in  std_logic;  -- sync reset, active high
    valid_src : in  std_logic;
    ready_src : out std_logic;
    data_src  : in  std_logic_vector(G_WIDTH - 1 downto 0);
    -- destination domain
    clk_dst   : in  std_logic;
    rst_dst   : in  std_logic;  -- sync reset, active high
    valid_dst : out std_logic;
    data_dst  : out std_logic_vector(G_WIDTH - 1 downto 0)
  );
end entity cdc_handshake;

architecture rtl of cdc_handshake is

  -- source domain
  signal req_toggle : std_logic := '0';
  signal ack_sync   : std_logic;
  signal ready_i    : std_logic;
  signal data_reg   : std_logic_vector(G_WIDTH - 1 downto 0) := (others => '0');

  -- destination domain
  signal req_sync   : std_logic;
  signal req_q      : std_logic := '0';
  signal ack_toggle : std_logic := '0';

begin

  ready_i   <= not (req_toggle xor ack_sync);
  ready_src <= ready_i;

  -- source: capture data and toggle the request
  p_src : process (clk_src)
  begin
    if rising_edge(clk_src) then
      if rst_src = '1' then
        req_toggle <= '0';
      elsif valid_src = '1' and ready_i = '1' then
        data_reg   <= data_src;
        req_toggle <= not req_toggle;
      end if;
    end if;
  end process;

  -- request crossing
  u_sync_req : entity work.cdc_sync_bit
    generic map (
      G_STAGES    => G_STAGES,
      G_RESET_VAL => '0'
    )
    port map (
      clk_dst => clk_dst,
      rst_dst => rst_dst,
      din     => req_toggle,
      dout    => req_sync
    );

  -- destination: detect request, sample the (stable) data, acknowledge
  p_dst : process (clk_dst)
  begin
    if rising_edge(clk_dst) then
      if rst_dst = '1' then
        req_q      <= '0';
        ack_toggle <= '0';
        valid_dst  <= '0';
      else
        req_q     <= req_sync;
        valid_dst <= '0';
        if (req_sync xor req_q) = '1' then
          data_dst   <= data_reg;  -- stable: held by the source until ack
          valid_dst  <= '1';
          ack_toggle <= not ack_toggle;
        end if;
      end if;
    end if;
  end process;

  -- acknowledge crossing back to the source
  u_sync_ack : entity work.cdc_sync_bit
    generic map (
      G_STAGES    => G_STAGES,
      G_RESET_VAL => '0'
    )
    port map (
      clk_dst => clk_src,
      rst_dst => rst_src,
      din     => ack_toggle,
      dout    => ack_sync
    );

end architecture rtl;
