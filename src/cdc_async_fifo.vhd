--------------------------------------------------------------------------------
-- cdc_async_fifo.vhd
--
-- Asynchronous (dual-clock) FIFO with gray-coded pointers, after the classic
-- Cummings architecture. Depth = 2**G_ADDR_WIDTH. Storage is a dpram.
--
-- Write side: a word is stored on the clk_wr edge where wr_en = '1' and
-- full = '0' (writes while full are ignored).
--
-- Read side: first-word fall-through (show-ahead). Whenever empty = '0'
-- (equivalently rd_valid = '1') the oldest word is already present on
-- rd_data; rd_en = '1' pops it and the next word appears on the following
-- clk_rd cycle (full throughput, one word per cycle). A prefetch stage keeps
-- the storage BRAM-friendly; total capacity is 2**G_ADDR_WIDTH + 1 words.
--
-- 'full' and 'empty' are pessimistic but never wrong: full may stay asserted
-- a few cycles after the reader freed space, empty a few cycles after the
-- writer stored data. No data is ever lost or duplicated.
--
-- Both resets are assumed to be asserted/released together (overlapping);
-- neither side may be used while the other is still in reset.
--
-- Constraints: the gray pointer crossings end in cdc_sync_bit chains
-- (set_max_delay -datapath_only recommended); the RAM read path crosses
-- from clk_wr writes to clk_rd reads and is protected by the pointers.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cdc_pkg.bin2gray;

entity cdc_async_fifo is
  generic (
    G_DATA_WIDTH : positive := 8;
    G_ADDR_WIDTH : positive := 4;  -- depth = 2**G_ADDR_WIDTH
    G_STAGES     : positive := 2   -- synchronizer stages per pointer bit
  );
  port (
    -- write (source) domain
    clk_wr   : in  std_logic;
    rst_wr   : in  std_logic;  -- sync reset, active high
    wr_en    : in  std_logic;
    wr_data  : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    full     : out std_logic;
    -- read (destination) domain
    clk_rd   : in  std_logic;
    rst_rd   : in  std_logic;  -- sync reset, active high
    rd_en    : in  std_logic;                                    -- pop
    rd_data  : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);  -- head word
    rd_valid : out std_logic;                                    -- = not empty
    empty    : out std_logic
  );
end entity cdc_async_fifo;

architecture rtl of cdc_async_fifo is

  -- pointers carry one extra MSB to distinguish full from empty
  constant C_PTR_W : positive := G_ADDR_WIDTH + 1;

  -- write domain
  signal wbin, wbin_next   : unsigned(C_PTR_W - 1 downto 0) := (others => '0');
  signal wgray, wgray_next : unsigned(C_PTR_W - 1 downto 0) := (others => '0');
  signal rgray_w           : unsigned(C_PTR_W - 1 downto 0);  -- rgray synced to clk_wr
  signal full_cmp          : unsigned(C_PTR_W - 1 downto 0);
  signal full_i            : std_logic := '0';
  signal wr_ok             : std_logic;

  -- read domain
  signal rbin, rbin_next   : unsigned(C_PTR_W - 1 downto 0) := (others => '0');
  signal rgray, rgray_next : unsigned(C_PTR_W - 1 downto 0) := (others => '0');
  signal wgray_r           : unsigned(C_PTR_W - 1 downto 0);  -- wgray synced to clk_rd
  signal empty_i           : std_logic := '1';  -- RAM (core) empty
  signal out_valid         : std_logic := '0';  -- rd_data holds the head word
  signal pop, fetch        : std_logic;

begin

  ------------------------------------------------------------------------------
  -- write domain
  ------------------------------------------------------------------------------
  wr_ok      <= wr_en and not full_i;
  wbin_next  <= wbin + 1 when wr_ok = '1' else wbin;
  wgray_next <= bin2gray(wbin_next);

  -- full when the next write gray pointer equals the synced read gray pointer
  -- with its two MSBs inverted
  full_cmp <= (not rgray_w(C_PTR_W - 1 downto C_PTR_W - 2))
              & rgray_w(C_PTR_W - 3 downto 0);

  p_wr : process (clk_wr)
  begin
    if rising_edge(clk_wr) then
      if rst_wr = '1' then
        wbin   <= (others => '0');
        wgray  <= (others => '0');
        full_i <= '0';
      else
        wbin  <= wbin_next;
        wgray <= wgray_next;
        if wgray_next = full_cmp then
          full_i <= '1';
        else
          full_i <= '0';
        end if;
      end if;
    end if;
  end process;

  full <= full_i;

  ------------------------------------------------------------------------------
  -- read domain (first-word fall-through)
  --
  -- The RAM output register doubles as the show-ahead stage: 'fetch' issues a
  -- RAM read so the next word lands on rd_data one cycle later, either to
  -- fill an empty output stage or to replace a word being popped.
  ------------------------------------------------------------------------------
  pop   <= rd_en and out_valid;
  fetch <= (not empty_i) and (pop or (not out_valid));

  rbin_next  <= rbin + 1 when fetch = '1' else rbin;
  rgray_next <= bin2gray(rbin_next);

  p_rd : process (clk_rd)
  begin
    if rising_edge(clk_rd) then
      if rst_rd = '1' then
        rbin      <= (others => '0');
        rgray     <= (others => '0');
        empty_i   <= '1';
        out_valid <= '0';
      else
        rbin  <= rbin_next;
        rgray <= rgray_next;
        if rgray_next = wgray_r then
          empty_i <= '1';
        else
          empty_i <= '0';
        end if;
        if fetch = '1' then
          out_valid <= '1';
        elsif pop = '1' then
          out_valid <= '0';
        end if;
      end if;
    end if;
  end process;

  rd_valid <= out_valid;
  empty    <= not out_valid;

  ------------------------------------------------------------------------------
  -- gray pointer crossings (one 2-flop chain per bit; gray coding guarantees
  -- at most one bit changes per clock, so the sampled value is always valid)
  ------------------------------------------------------------------------------
  gen_sync_ptr : for i in 0 to C_PTR_W - 1 generate

    u_sync_w2r : entity work.cdc_sync_bit
      generic map (
        G_STAGES    => G_STAGES,
        G_RESET_VAL => '0'
      )
      port map (
        clk_dst => clk_rd,
        rst_dst => rst_rd,
        din     => wgray(i),
        dout    => wgray_r(i)
      );

    u_sync_r2w : entity work.cdc_sync_bit
      generic map (
        G_STAGES    => G_STAGES,
        G_RESET_VAL => '0'
      )
      port map (
        clk_dst => clk_wr,
        rst_dst => rst_wr,
        din     => rgray(i),
        dout    => rgray_w(i)
      );

  end generate;

  ------------------------------------------------------------------------------
  -- storage
  ------------------------------------------------------------------------------
  u_ram : entity work.dpram
    generic map (
      G_DATA_WIDTH => G_DATA_WIDTH,
      G_ADDR_WIDTH => G_ADDR_WIDTH,
      G_OUTPUT_REG => false
    )
    port map (
      clk_a  => clk_wr,
      en_a   => '1',
      we_a   => wr_ok,
      addr_a => std_logic_vector(wbin(G_ADDR_WIDTH - 1 downto 0)),
      din_a  => wr_data,
      clk_b  => clk_rd,
      en_b   => fetch,
      addr_b => std_logic_vector(rbin(G_ADDR_WIDTH - 1 downto 0)),
      dout_b => rd_data
    );

end architecture rtl;
