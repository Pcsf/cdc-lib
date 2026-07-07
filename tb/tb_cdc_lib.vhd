--------------------------------------------------------------------------------
-- tb_cdc_lib.vhd
--
-- Self-checking smoke test for the CDC library. Two unrelated clocks:
--   clk_a (source, 100 MHz) and clk_b (destination, ~135 MHz).
--
-- Tests:
--   T1: cdc_sync_bit     - level crossing both directions of the level
--   T2: cdc_sync_pulse   - 5 active-high pulses and 3 active-low pulses
--   T3: cdc_handshake    - 8 words transferred in order
--   T4: cdc_async_fifo   - fill to full, drain to empty, then 32-word stream
--   T5: dpram            - 16 locations written on port A, read on port B
--   T6: cdc_pingpong     - 3 banks written/committed, read/released; checks
--                          wr_ready = '0' while both banks are outstanding
--
-- Any mismatch stops the simulation with severity failure; on success the
-- simulation prints "ALL TESTS PASSED" and ends.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_cdc_lib is
end entity tb_cdc_lib;

architecture sim of tb_cdc_lib is

  signal clk_a    : std_logic := '0';
  signal clk_b    : std_logic := '0';
  signal rst_a    : std_logic := '1';
  signal rst_b    : std_logic := '1';
  signal sim_done : boolean   := false;

  -- T1: sync bit
  signal sb_din  : std_logic := '0';
  signal sb_dout : std_logic;

  -- T2: pulse sync
  signal ph_src, ph_dst, ph_busy : std_logic;
  signal pl_src                  : std_logic := '1';
  signal pl_dst, pl_busy         : std_logic;
  signal ph_count, pl_count      : integer := 0;

  -- T3: handshake
  signal hs_valid_src : std_logic := '0';
  signal hs_ready_src : std_logic;
  signal hs_valid_dst : std_logic;
  signal hs_data_src  : std_logic_vector(7 downto 0) := (others => '0');
  signal hs_data_dst  : std_logic_vector(7 downto 0);
  signal hs_rx_count  : integer := 0;

  -- T4: async fifo
  signal ff_wr_en, ff_full     : std_logic := '0';
  signal ff_rd_en, ff_empty    : std_logic;
  signal ff_rd_valid           : std_logic;
  signal ff_wr_data, ff_rd_data : std_logic_vector(7 downto 0) := (others => '0');
  signal rd_pause              : std_logic := '1';
  signal ff_rx_count           : integer := 0;

  -- T5: dpram
  signal ram_we_a  : std_logic := '0';
  signal ram_addr_a, ram_addr_b : std_logic_vector(3 downto 0) := (others => '0');
  signal ram_din_a, ram_dout_b  : std_logic_vector(7 downto 0) := (others => '0');

  -- T6: ping-pong buffer
  signal pp_wr_ready, pp_rd_valid : std_logic;
  signal pp_wr_en, pp_wr_commit   : std_logic := '0';
  signal pp_rd_release            : std_logic := '0';
  signal pp_wr_addr, pp_rd_addr   : std_logic_vector(3 downto 0) := (others => '0');
  signal pp_wr_data, pp_rd_data   : std_logic_vector(7 downto 0) := (others => '0');
  signal pp_start, pp_done        : boolean := false;

begin

  clk_a <= not clk_a after 5.0 ns when not sim_done else '0';
  clk_b <= not clk_b after 3.7 ns when not sim_done else '0';

  ------------------------------------------------------------------------------
  -- devices under test
  ------------------------------------------------------------------------------
  u_sync_bit : entity work.cdc_sync_bit
    generic map (G_STAGES => 2, G_RESET_VAL => '0')
    port map (
      clk_dst => clk_b, rst_dst => rst_b,
      din     => sb_din, dout => sb_dout
    );

  u_pulse_hi : entity work.cdc_sync_pulse
    generic map (G_STAGES => 2, G_ACTIVE_LEVEL => '1')
    port map (
      clk_src => clk_a, rst_src => rst_a, pulse_src => ph_src, busy => ph_busy,
      clk_dst => clk_b, rst_dst => rst_b, pulse_dst => ph_dst
    );

  u_pulse_lo : entity work.cdc_sync_pulse
    generic map (G_STAGES => 2, G_ACTIVE_LEVEL => '0')
    port map (
      clk_src => clk_a, rst_src => rst_a, pulse_src => pl_src, busy => pl_busy,
      clk_dst => clk_b, rst_dst => rst_b, pulse_dst => pl_dst
    );

  u_handshake : entity work.cdc_handshake
    generic map (G_WIDTH => 8, G_STAGES => 2)
    port map (
      clk_src => clk_a, rst_src => rst_a,
      valid_src => hs_valid_src, ready_src => hs_ready_src, data_src => hs_data_src,
      clk_dst => clk_b, rst_dst => rst_b,
      valid_dst => hs_valid_dst, data_dst => hs_data_dst
    );

  u_fifo : entity work.cdc_async_fifo
    generic map (G_DATA_WIDTH => 8, G_ADDR_WIDTH => 4, G_STAGES => 2)
    port map (
      clk_wr => clk_a, rst_wr => rst_a,
      wr_en => ff_wr_en, wr_data => ff_wr_data, full => ff_full,
      clk_rd => clk_b, rst_rd => rst_b,
      rd_en => ff_rd_en, rd_data => ff_rd_data, rd_valid => ff_rd_valid,
      empty => ff_empty
    );

  u_dpram : entity work.dpram
    generic map (G_DATA_WIDTH => 8, G_ADDR_WIDTH => 4, G_OUTPUT_REG => false)
    port map (
      clk_a => clk_a, en_a => '1', we_a => ram_we_a,
      addr_a => ram_addr_a, din_a => ram_din_a,
      clk_b => clk_b, en_b => '1', addr_b => ram_addr_b, dout_b => ram_dout_b
    );

  u_pingpong : entity work.cdc_pingpong
    generic map (G_DATA_WIDTH => 8, G_ADDR_WIDTH => 4, G_STAGES => 2, G_OUTPUT_REG => false)
    port map (
      clk_wr => clk_a, rst_wr => rst_a,
      wr_ready => pp_wr_ready, wr_en => pp_wr_en,
      wr_addr => pp_wr_addr, wr_data => pp_wr_data, wr_commit => pp_wr_commit,
      clk_rd => clk_b, rst_rd => rst_b,
      rd_valid => pp_rd_valid, rd_addr => pp_rd_addr, rd_data => pp_rd_data,
      rd_release => pp_rd_release
    );

  ------------------------------------------------------------------------------
  -- destination-domain monitors
  ------------------------------------------------------------------------------
  p_mon_pulse : process (clk_b)
  begin
    if rising_edge(clk_b) and rst_b = '0' then
      if ph_dst = '1' then
        ph_count <= ph_count + 1;
      end if;
      if pl_dst = '0' then
        pl_count <= pl_count + 1;
      end if;
    end if;
  end process;

  p_mon_hs : process (clk_b)
  begin
    if rising_edge(clk_b) and rst_b = '0' then
      if hs_valid_dst = '1' then
        assert hs_data_dst = std_logic_vector(to_unsigned(hs_rx_count, 8))
          report "T3 handshake: data mismatch at word " & integer'image(hs_rx_count)
          severity failure;
        hs_rx_count <= hs_rx_count + 1;
      end if;
    end if;
  end process;

  -- FIFO reader: pop whenever data is available and not paused
  ff_rd_en <= (not ff_empty) and (not rd_pause);

  -- FWFT: rd_data already shows the head word, so check it on the pop edge
  p_mon_fifo : process (clk_b)
  begin
    if rising_edge(clk_b) and rst_b = '0' then
      if ff_rd_valid = '1' and ff_rd_en = '1' then
        assert ff_rd_data = std_logic_vector(to_unsigned(ff_rx_count mod 256, 8))
          report "T4 fifo: data mismatch at word " & integer'image(ff_rx_count)
          severity failure;
        ff_rx_count <= ff_rx_count + 1;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- T6 reader: consumes 3 banks; the first is held long enough for the writer
  -- to commit the second bank and hit the both-banks-outstanding condition
  ------------------------------------------------------------------------------
  p_pp_read : process
  begin
    wait until pp_start;
    for b in 0 to 2 loop
      wait until rising_edge(clk_b) and pp_rd_valid = '1';
      if b = 0 then
        wait for 400 ns;  -- stall so the writer fills+commits bank 1 meanwhile
      end if;
      for i in 0 to 15 loop
        pp_rd_addr <= std_logic_vector(to_unsigned(i, 4));
        wait until rising_edge(clk_b);
        wait until rising_edge(clk_b);
        assert pp_rd_data = std_logic_vector(to_unsigned(b * 16 + i, 8))
          report "T6 pingpong: mismatch bank " & integer'image(b)
               & " address " & integer'image(i)
          severity failure;
      end loop;
      pp_rd_release <= '1';
      wait until rising_edge(clk_b);
      pp_rd_release <= '0';
    end loop;
    pp_done <= true;
    wait;
  end process;

  ------------------------------------------------------------------------------
  -- main stimulus / checker
  ------------------------------------------------------------------------------
  p_main : process
  begin
    ph_src <= '0';
    wait for 100 ns;
    wait until rising_edge(clk_a);
    rst_a <= '0';
    wait until rising_edge(clk_b);
    rst_b <= '0';
    wait for 50 ns;

    -- T1: level synchronizer
    sb_din <= '1';
    wait for 100 ns;
    assert sb_dout = '1' report "T1 sync_bit: rising level not seen" severity failure;
    sb_din <= '0';
    wait for 100 ns;
    assert sb_dout = '0' report "T1 sync_bit: falling level not seen" severity failure;
    report "T1 cdc_sync_bit PASS";

    -- T2a: active-high pulses
    for i in 1 to 5 loop
      wait until rising_edge(clk_a) and ph_busy = '0';
      ph_src <= '1';
      wait until rising_edge(clk_a);
      ph_src <= '0';
    end loop;
    wait for 300 ns;
    assert ph_count = 5
      report "T2 pulse (high): expected 5 pulses, got " & integer'image(ph_count)
      severity failure;

    -- T2b: active-low pulses
    for i in 1 to 3 loop
      wait until rising_edge(clk_a) and pl_busy = '0';
      pl_src <= '0';
      wait until rising_edge(clk_a);
      pl_src <= '1';
    end loop;
    wait for 300 ns;
    assert pl_count = 3
      report "T2 pulse (low): expected 3 pulses, got " & integer'image(pl_count)
      severity failure;
    report "T2 cdc_sync_pulse PASS";

    -- T3: handshake, 8 words in order
    for i in 0 to 7 loop
      wait until rising_edge(clk_a) and hs_ready_src = '1';
      hs_valid_src <= '1';
      hs_data_src  <= std_logic_vector(to_unsigned(i, 8));
      wait until rising_edge(clk_a);
      hs_valid_src <= '0';
    end loop;
    wait for 500 ns;
    assert hs_rx_count = 8
      report "T3 handshake: expected 8 words, got " & integer'image(hs_rx_count)
      severity failure;
    report "T3 cdc_handshake PASS";

    -- T4a: fill the FIFO (reader paused), check full
    -- FWFT capacity = RAM depth + 1 (prefetch stage) = 17 words
    rd_pause <= '1';
    for i in 0 to 16 loop
      wait until rising_edge(clk_a) and ff_full = '0';
      ff_wr_en   <= '1';
      ff_wr_data <= std_logic_vector(to_unsigned(i, 8));
      wait until rising_edge(clk_a);
      ff_wr_en <= '0';
    end loop;
    wait for 100 ns;
    assert ff_full = '1' report "T4 fifo: full not asserted after 17 writes" severity failure;

    -- T4b: drain, check empty
    rd_pause <= '0';
    wait until ff_rx_count = 17;
    wait for 100 ns;
    assert ff_empty = '1' report "T4 fifo: empty not asserted after drain" severity failure;

    -- T4c: 32-word stream with concurrent read
    for i in 17 to 48 loop
      wait until rising_edge(clk_a) and ff_full = '0';
      ff_wr_en   <= '1';
      ff_wr_data <= std_logic_vector(to_unsigned(i mod 256, 8));
      wait until rising_edge(clk_a);
      ff_wr_en <= '0';
    end loop;
    wait until ff_rx_count = 49;
    wait for 100 ns;
    assert ff_empty = '1' report "T4 fifo: empty not asserted after stream" severity failure;
    report "T4 cdc_async_fifo PASS";

    -- T5: dual-port RAM, write on A then read back on B
    wait until rising_edge(clk_a);
    for i in 0 to 15 loop
      ram_we_a   <= '1';
      ram_addr_a <= std_logic_vector(to_unsigned(i, 4));
      ram_din_a  <= std_logic_vector(to_unsigned(i * 5 + 3, 8));
      wait until rising_edge(clk_a);
    end loop;
    ram_we_a <= '0';
    wait for 50 ns;
    for i in 0 to 15 loop
      ram_addr_b <= std_logic_vector(to_unsigned(i, 4));
      wait until rising_edge(clk_b);
      wait until rising_edge(clk_b);
      assert ram_dout_b = std_logic_vector(to_unsigned(i * 5 + 3, 8))
        report "T5 dpram: mismatch at address " & integer'image(i)
        severity failure;
    end loop;
    report "T5 dpram PASS";

    -- T6: ping-pong buffer, 3 banks (wraps the 2-bank pointers)
    pp_start <= true;
    for b in 0 to 2 loop
      wait until rising_edge(clk_a) and pp_wr_ready = '1';
      for i in 0 to 15 loop
        pp_wr_en   <= '1';
        pp_wr_addr <= std_logic_vector(to_unsigned(i, 4));
        pp_wr_data <= std_logic_vector(to_unsigned(b * 16 + i, 8));
        wait until rising_edge(clk_a);
      end loop;
      pp_wr_en  <= '0';
      pp_wr_commit <= '1';
      wait until rising_edge(clk_a);
      pp_wr_commit <= '0';
      if b = 1 then
        -- reader still holds bank 0: both banks outstanding, writer must stall
        wait for 50 ns;
        assert pp_wr_ready = '0'
          report "T6 pingpong: wr_ready not deasserted with both banks outstanding"
          severity failure;
      end if;
    end loop;
    wait until pp_done;
    report "T6 cdc_pingpong PASS";

    report "ALL TESTS PASSED";
    sim_done <= true;
    wait;
  end process;

end architecture sim;
