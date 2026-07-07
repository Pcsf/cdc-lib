--------------------------------------------------------------------------------
-- cdc_sync_bit.vhd
--
-- Single-bit level synchronizer: N-stage flip-flop chain (default 2).
--
-- Use for slowly-changing level signals only. The input must be driven by a
-- register in the source domain (no combinational glitches) and must remain
-- stable for more than one destination clock period to be reliably sampled.
--
-- Synthesis attributes mark the chain as a synchronizer for Xilinx (ASYNC_REG,
-- no SRL extraction) and Intel/Altera (forced synchronizer identification).
--
-- Constraints: set a false path (or max delay) on the path into sync_regs(0).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity cdc_sync_bit is
  generic (
    G_STAGES    : positive  := 2;   -- number of synchronizer stages (>= 2)
    G_RESET_VAL : std_logic := '0'  -- value of the chain during/after reset
  );
  port (
    clk_dst : in  std_logic;  -- destination clock
    rst_dst : in  std_logic;  -- destination sync reset, active high
    din     : in  std_logic;  -- input from the source clock domain
    dout    : out std_logic   -- synchronized output
  );
end entity cdc_sync_bit;

architecture rtl of cdc_sync_bit is

  signal sync_regs : std_logic_vector(G_STAGES - 1 downto 0) := (others => G_RESET_VAL);

  attribute async_reg : string;
  attribute async_reg of sync_regs : signal is "true";

  attribute shreg_extract : string;
  attribute shreg_extract of sync_regs : signal is "no";

  attribute altera_attribute : string;
  attribute altera_attribute of sync_regs : signal is
    "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";

begin

  p_sync : process (clk_dst)
  begin
    if rising_edge(clk_dst) then
      if rst_dst = '1' then
        sync_regs <= (others => G_RESET_VAL);
      else
        sync_regs <= sync_regs(G_STAGES - 2 downto 0) & din;
      end if;
    end if;
  end process;

  dout <= sync_regs(G_STAGES - 1);

end architecture rtl;
