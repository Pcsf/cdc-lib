--------------------------------------------------------------------------------
-- cdc_sync_pulse.vhd
--
-- Pulse synchronizer using the toggle scheme. A single-cycle pulse in the
-- source domain produces exactly one single-cycle pulse in the destination
-- domain, regardless of the clock frequency ratio.
--
-- G_ACTIVE_LEVEL selects the pulse polarity for both input and output:
--   '1' : idle low,  pulse is a one-cycle '1' (active high)
--   '0' : idle high, pulse is a one-cycle '0' (active low)
--
-- The 'busy' flag (source domain, always active high) is asserted while a
-- pulse is still in flight through the round-trip feedback path. Pulses
-- applied while busy = '1' are ignored; wait for busy = '0' before issuing
-- the next pulse.
--
-- Both resets are assumed to be asserted/released together (overlapping).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity cdc_sync_pulse is
  generic (
    G_STAGES       : positive  := 2;   -- synchronizer stages per crossing
    G_ACTIVE_LEVEL : std_logic := '1'  -- '1' active high, '0' active low
  );
  port (
    -- source domain
    clk_src   : in  std_logic;
    rst_src   : in  std_logic;  -- sync reset, active high
    pulse_src : in  std_logic;  -- one-cycle pulse at G_ACTIVE_LEVEL
    busy      : out std_logic;  -- '1' while crossing in progress
    -- destination domain
    clk_dst   : in  std_logic;
    rst_dst   : in  std_logic;  -- sync reset, active high
    pulse_dst : out std_logic   -- one-cycle pulse at G_ACTIVE_LEVEL
  );
end entity cdc_sync_pulse;

architecture rtl of cdc_sync_pulse is

  -- source domain
  signal toggle_src : std_logic := '0';
  signal toggle_fb  : std_logic;  -- round-trip feedback, synced to clk_src
  signal busy_i     : std_logic;

  -- destination domain
  signal toggle_dst : std_logic;         -- toggle synced to clk_dst
  signal toggle_q   : std_logic := '0';  -- delayed for edge detection
  signal pulse_r    : std_logic := not G_ACTIVE_LEVEL;

begin

  busy_i <= toggle_src xor toggle_fb;
  busy   <= busy_i;

  -- source: convert accepted pulse into a toggle
  p_src : process (clk_src)
  begin
    if rising_edge(clk_src) then
      if rst_src = '1' then
        toggle_src <= '0';
      elsif pulse_src = G_ACTIVE_LEVEL and busy_i = '0' then
        toggle_src <= not toggle_src;
      end if;
    end if;
  end process;

  -- toggle crossing into the destination domain
  u_sync_dst : entity work.cdc_sync_bit
    generic map (
      G_STAGES    => G_STAGES,
      G_RESET_VAL => '0'
    )
    port map (
      clk_dst => clk_dst,
      rst_dst => rst_dst,
      din     => toggle_src,
      dout    => toggle_dst
    );

  -- destination: edge detect on the synchronized toggle
  p_dst : process (clk_dst)
  begin
    if rising_edge(clk_dst) then
      if rst_dst = '1' then
        toggle_q <= '0';
        pulse_r  <= not G_ACTIVE_LEVEL;
      else
        toggle_q <= toggle_dst;
        if (toggle_dst xor toggle_q) = '1' then
          pulse_r <= G_ACTIVE_LEVEL;
        else
          pulse_r <= not G_ACTIVE_LEVEL;
        end if;
      end if;
    end if;
  end process;

  pulse_dst <= pulse_r;

  -- round-trip feedback so the source knows when the crossing completed
  u_sync_fb : entity work.cdc_sync_bit
    generic map (
      G_STAGES    => G_STAGES,
      G_RESET_VAL => '0'
    )
    port map (
      clk_dst => clk_src,
      rst_dst => rst_src,
      din     => toggle_q,
      dout    => toggle_fb
    );

end architecture rtl;
