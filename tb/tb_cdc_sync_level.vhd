--------------------------------------------------------------------------------
-- tb_cdc_sync_level.vhd
--
-- Self-checking test bench for cdc_sync_level, for one polarity and one pair
-- of clock periods. tb_cdc_lib instantiates it once per combination and
-- waits for 'done'.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity tb_cdc_sync_level is
  generic (
    G_ACTIVE_LEVEL : std_logic := '1';
    G_T_SRC_PS     : positive  := 2000;   -- clk_src period in ps
    G_T_DST_PS     : positive  := 37000   -- clk_dst period in ps
  );
  port (
    done : out boolean
  );
end entity tb_cdc_sync_level;

architecture sim of tb_cdc_sync_level is

  constant C_ACT  : std_logic := G_ACTIVE_LEVEL;
  constant C_IDLE : std_logic := not G_ACTIVE_LEVEL;
  constant T_SRC  : time := G_T_SRC_PS * 1 ps;
  constant T_DST  : time := G_T_DST_PS * 1 ps;
  -- Upper bound on the handshake round trip with 2 synchronizer stages.
  constant T_RT   : time := 5 * (T_SRC + T_DST);

  type t_ints  is array (natural range <>) of positive;
  type t_times is array (0 to 63) of time;
  -- Input pulse widths in clk_src cycles, short to far beyond T_RT.
  constant C_WIDTHS : t_ints := (1, 2, 3, 4, 6, 9, 14, 20, 35, 60, 100, 160, 300);

  signal clk_src, clk_dst : std_logic := '0';
  signal rst_src, rst_dst : std_logic := '1';
  signal pulse_src        : std_logic := C_IDLE;
  signal busy, drop       : std_logic;
  signal pulse_dst        : std_logic;
  signal done_i           : boolean := false;

  signal n_dst  : natural := 0;                    -- completed output pulses
  signal out_w  : t_times := (others => 0 ns);     -- their widths
  signal n_drop : natural := 0;
  signal errors : natural := 0;

begin

  done <= done_i;

  clk_src <= not clk_src after T_SRC / 2 when not done_i else '0';
  clk_dst <= not clk_dst after T_DST / 2 when not done_i else '0';

  dut : entity work.cdc_sync_level
    generic map (G_STAGES => 2, G_ACTIVE_LEVEL => G_ACTIVE_LEVEL)
    port map (
      clk_src => clk_src, rst_src => rst_src, pulse_src => pulse_src,
      busy => busy, drop => drop,
      clk_dst => clk_dst, rst_dst => rst_dst, pulse_dst => pulse_dst);

  -- Count output pulses and record how long each one stayed active.
  p_mon_dst : process (clk_dst)
    variable run : natural := 0;
  begin
    if rising_edge(clk_dst) then
      if pulse_dst /= C_ACT and pulse_dst /= C_IDLE then
        report "pulse_dst not a clean level" severity error;
        errors <= errors + 1;
      end if;
      if pulse_dst = C_ACT then
        run := run + 1;
      elsif run > 0 then
        if n_dst <= t_times'high then
          out_w(n_dst) <= run * T_DST;
        end if;
        n_dst <= n_dst + 1;
        run   := 0;
      end if;
    end if;
  end process;

  p_mon_src : process (clk_src)
  begin
    if rising_edge(clk_src) and drop = '1' then
      n_drop <= n_drop + 1;
    end if;
  end process;

  p_stim : process
    variable n_sent : natural := 0;
    variable fails  : natural := 0;
    variable w_in   : time;

    procedure tick_src (n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk_src);
      end loop;
    end procedure;

    procedure tick_dst (n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk_dst);
      end loop;
    end procedure;

    -- One pulse: active for 'width' src cycles, then idle for 'gap'.
    procedure send (width : positive; gap : positive := 1) is
    begin
      pulse_src <= C_ACT;
      tick_src(width);
      pulse_src <= C_IDLE;
      tick_src(gap);
      n_sent := n_sent + 1;
    end procedure;

    -- Long enough for anything in flight to land on both sides.
    procedure settle is
    begin
      tick_src(8);
      tick_dst(8);
      tick_src;
      while busy /= '0' loop
        tick_src;
      end loop;
      tick_dst(4);
    end procedure;

    procedure check (cond : boolean; msg : string) is
    begin
      if not cond then
        report msg severity error;
        fails := fails + 1;
      end if;
    end procedure;

  begin
    tick_src(4);
    tick_dst(4);
    rst_src <= '0';
    rst_dst <= '0';

    -- 1. Idle input after reset: no output pulse.
    settle;
    check(n_dst = 0, "spurious pulse after reset");

    -- 2. Separated pulses: each arrives once; a pulse longer than the
    --    round trip keeps its width to within one clk_dst cycle; a shorter
    --    one lasts at least one clk_dst cycle and at most the round trip.
    for i in C_WIDTHS'range loop
      settle;
      send(C_WIDTHS(i));
    end loop;
    settle;
    check(n_drop = 0, "drop flagged on separated pulses");
    check(n_dst = n_sent,
          "separated pulses: sent " & integer'image(n_sent) &
          ", received " & integer'image(n_dst));
    for i in C_WIDTHS'range loop
      w_in := C_WIDTHS(i) * T_SRC;
      check(out_w(i) >= T_DST, "pulse " & integer'image(i) &
            " shorter than one clk_dst cycle");
      if w_in >= T_RT then
        check(abs (out_w(i) - w_in) <= T_DST,
              "pulse " & integer'image(i) & " in " & time'image(w_in) &
              ", out " & time'image(out_w(i)));
      else
        check(out_w(i) >= w_in - T_DST and out_w(i) <= T_RT + 2 * T_DST,
              "short pulse " & integer'image(i) & " in " & time'image(w_in) &
              ", out " & time'image(out_w(i)));
      end if;
    end loop;

    -- 3. Pulses and gaps of 1 to 3 src cycles, ignoring busy: each one is
    --    either a separate output pulse or flagged by drop.
    for i in 0 to 39 loop
      send(1 + i mod 3, 1 + (i / 3) mod 3);
    end loop;
    settle;
    check(n_dst + n_drop = n_sent,
          "burst: sent " & integer'image(n_sent) & ", received " &
          integer'image(n_dst) & ", dropped " & integer'image(n_drop));

    -- 4. Resetting one side alone, input idle: no output pulse, and the
    --    link still works afterwards.
    rst_src <= '1';
    tick_src(5);
    rst_src <= '0';
    settle;
    rst_dst <= '1';
    tick_dst(5);
    rst_dst <= '0';
    settle;
    check(n_dst + n_drop = n_sent, "pulse from a one-sided reset");
    send(3);
    settle;
    check(n_dst + n_drop = n_sent, "link dead after one-sided reset");

    -- 5. An input already active when rst_src releases is one pulse.
    --    While rst_src is held the output stays idle.
    rst_src   <= '1';
    pulse_src <= C_ACT;
    tick_src(8);
    tick_dst(12);
    check(pulse_dst = C_IDLE, "output active while rst_src is held");
    tick_src;
    rst_src   <= '0';
    tick_src(4);
    pulse_src <= C_IDLE;
    n_sent := n_sent + 1;
    settle;
    check(n_dst + n_drop = n_sent, "input active across reset release lost");

    -- 6. Input held active: the output stays active, goes idle while
    --    rst_dst is asserted, and comes back when it releases.
    pulse_src <= C_ACT;
    tick_src(8);
    tick_dst(12);
    check(pulse_dst = C_ACT, "output not active while the input is held");
    rst_dst <= '1';
    tick_dst(3);
    check(pulse_dst = C_IDLE, "output active while rst_dst is asserted");
    rst_dst <= '0';
    tick_dst(3);
    check(pulse_dst = C_ACT, "output did not return after rst_dst");
    tick_src;
    pulse_src <= C_IDLE;
    n_sent := n_sent + 2;   -- one input pulse, split in two by the reset
    settle;
    check(pulse_dst = C_IDLE, "output stuck active");
    check(n_dst + n_drop = n_sent, "held input: wrong pulse count");

    fails := fails + errors;
    done_i <= true;
    if fails = 0 then
      report "T7 cdc_sync_level PASS active=" & std_logic'image(G_ACTIVE_LEVEL) &
             " Tsrc=" & integer'image(G_T_SRC_PS) & "ps Tdst=" &
             integer'image(G_T_DST_PS) & "ps sent=" & integer'image(n_sent) &
             " received=" & integer'image(n_dst) &
             " dropped=" & integer'image(n_drop) &
             " out_width(1 src cycle)=" & time'image(out_w(0)) &
             " out_width(300 src cycles)=" & time'image(out_w(C_WIDTHS'high));
    else
      report "T7 cdc_sync_level FAIL: " & integer'image(fails) & " check(s)" severity failure;
    end if;
    wait;
  end process;

end architecture sim;
