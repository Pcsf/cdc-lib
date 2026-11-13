--------------------------------------------------------------------------------
-- cdc_sync_level.vhd
--
-- Level synchronizer for one bit, for any ratio of clk_src to clk_dst.
--
-- pulse_dst follows pulse_src: it stays at G_ACTIVE_LEVEL for as long as the
-- input does, and idles at the opposite level. No input pulse is lost,
-- however short it is against clk_dst.
--
-- The input is copied into 'hold', which crosses into clk_dst and comes back
-- to clk_src as 'ack'. 'hold' may rise only while ack = '0' and fall only
-- while ack = '1', so the destination has seen each level before the next
-- change. One round trip is about
--   (G_STAGES + 2) clk_dst + (G_STAGES + 1) clk_src cycles.
-- Consequences:
--   * a pulse longer than the round trip keeps its width to within one
--     clk_dst cycle;
--   * a shorter pulse is stretched to about the round trip;
--   * an idle gap shorter than the round trip is widened: the next pulse
--     starts late. One such pulse is remembered. A further pulse arriving
--     before the remembered one has started merges into it, and 'drop'
--     goes high for one clk_src cycle.
--
-- busy = '1' while a level change is in flight.
--
-- Resets are independent. rst_src makes the input read as idle; rst_dst
-- forces pulse_dst idle. Neither disturbs the handshake.
-- Relies on power-up initial values: FPGA targets, not ASIC.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity cdc_sync_level is
  generic (
    G_STAGES       : positive  := 2;   -- flip-flops per crossing (>= 2)
    G_ACTIVE_LEVEL : std_logic := '1'  -- '1' active high, '0' active low
  );
  port (
    -- source domain
    clk_src   : in  std_logic;
    rst_src   : in  std_logic;   -- synchronous, active high
    pulse_src : in  std_logic;   -- any width >= 1 clk_src cycle
    busy      : out std_logic;   -- active high
    drop      : out std_logic;   -- active high, one clk_src cycle
    -- destination domain
    clk_dst   : in  std_logic;
    rst_dst   : in  std_logic;   -- synchronous, active high
    pulse_dst : out std_logic
  );
end entity cdc_sync_level;

architecture rtl of cdc_sync_level is
  constant C_IDLE : std_logic := not G_ACTIVE_LEVEL;

  -- source domain, all active high
  signal act    : std_logic;          -- input is at the active level
  signal act_q  : std_logic := '0';
  signal hold   : std_logic := '0';   -- level sent to the destination
  signal pend   : std_logic := '0';   -- a pulse is waiting to start
  signal ack_s  : std_logic;
  signal drop_r : std_logic := '0';

  -- destination domain
  signal hold_s  : std_logic;
  signal hold_q  : std_logic := '0';
  signal pulse_r : std_logic := C_IDLE;
begin

  act <= '1' when pulse_src = G_ACTIVE_LEVEL and rst_src = '0' else '0';

  p_src : process (clk_src)
    variable new_pulse : boolean;
  begin
    if rising_edge(clk_src) then
      new_pulse := act = '1' and act_q = '0';
      act_q     <= act;
      drop_r    <= '0';

      if hold = '0' and ack_s = '0' and (act = '1' or pend = '1') then
        hold <= '1';
        pend <= '0';
        if new_pulse and pend = '1' then
          drop_r <= '1';
        end if;
      else
        if hold = '1' and ack_s = '1' and (act = '0' or pend = '1') then
          hold <= '0';
        end if;
        if new_pulse then
          if pend = '1' then
            drop_r <= '1';
          else
            pend <= '1';
          end if;
        end if;
      end if;

      if rst_src = '1' then
        pend <= '0';
      end if;
    end if;
  end process;

  -- The synchronizer resets stay inactive so a reset cannot fake a level.
  u_hold_sync : entity work.cdc_sync_bit
    generic map (G_STAGES => G_STAGES, G_RESET_VAL => '0')
    port map (clk_dst => clk_dst, rst_dst => '0', din => hold, dout => hold_s);

  p_dst : process (clk_dst)
  begin
    if rising_edge(clk_dst) then
      hold_q <= hold_s;
      if hold_s = '1' and rst_dst = '0' then
        pulse_r <= G_ACTIVE_LEVEL;
      else
        pulse_r <= C_IDLE;
      end if;
    end if;
  end process;

  u_ack_sync : entity work.cdc_sync_bit
    generic map (G_STAGES => G_STAGES, G_RESET_VAL => '0')
    port map (clk_dst => clk_src, rst_dst => '0', din => hold_q, dout => ack_s);

  busy      <= hold xor ack_s;
  drop      <= drop_r;
  pulse_dst <= pulse_r;
end architecture rtl;
