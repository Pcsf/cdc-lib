--------------------------------------------------------------------------------
-- cdc_pingpong.vhd
--
-- Ping-pong (double-bank) buffer for block transfers across clock domains,
-- built on dpram with gray-coded bank handshaking. Use it when the consumer
-- needs random access to a block of data (frames, lines, packets, sample
-- blocks) instead of the in-order stream a FIFO provides.
--
-- Write side: while wr_ready = '1' the writer owns a free bank and may write
-- it in any order (wr_en/wr_addr/wr_data). A one-cycle wr_commit pulse hands
-- the bank to the reader and switches to the other bank. wr_ready cannot
-- drop while a bank is being filled, only after wr_commit; commits and writes
-- while wr_ready = '0' are ignored.
--
-- Read side: rd_valid = '1' while a committed bank is mapped to the read
-- port; rd_data returns the word at rd_addr after 1 clk_rd cycle (2 with
-- G_OUTPUT_REG). A one-cycle rd_release pulse returns the bank to the writer.
--
-- Both banks may be outstanding at once: the writer fills the second bank
-- while the reader is still consuming the first.
--
-- Bank ownership is tracked with 2-bit gray-coded wr_commit/rd_release pointers,
-- exactly like the cdc_async_fifo pointers, so a bank is never written and
-- read at the same time.
--
-- Both resets are assumed to be asserted/released together (overlapping).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cdc_pkg.bin2gray;

entity cdc_pingpong is
  generic (
    G_DATA_WIDTH : positive := 8;
    G_ADDR_WIDTH : positive := 4;      -- per-bank depth = 2**G_ADDR_WIDTH
    G_STAGES     : positive := 2;      -- synchronizer stages per pointer bit
    G_OUTPUT_REG : boolean  := false   -- extra read output register
  );
  port (
    -- write (producer) domain
    clk_wr   : in  std_logic;
    rst_wr   : in  std_logic;  -- sync reset, active high
    wr_ready : out std_logic;  -- '1': a free bank is owned by the writer
    wr_en    : in  std_logic;
    wr_addr  : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    wr_data  : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    wr_commit : in  std_logic; -- one-cycle pulse: hand bank to the reader
    -- read (consumer) domain
    clk_rd   : in  std_logic;
    rst_rd   : in  std_logic;  -- sync reset, active high
    rd_valid : out std_logic;  -- '1': a committed bank is readable
    rd_addr  : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    rd_data  : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    rd_release : in  std_logic -- one-cycle pulse: return bank to the writer
  );
end entity cdc_pingpong;

architecture rtl of cdc_pingpong is

  -- 2-bit bank pointers: bit 0 selects the bank, bit 1 is the wrap bit that
  -- distinguishes "both banks free" from "both banks committed"
  signal wptr, wptr_next   : unsigned(1 downto 0) := (others => '0');
  signal wgray, wgray_next : unsigned(1 downto 0) := (others => '0');
  signal rgray_w           : unsigned(1 downto 0);  -- rgray synced to clk_wr
  signal full_i            : std_logic := '0';
  signal commit_ok         : std_logic;
  signal wr_ok             : std_logic;

  signal rptr, rptr_next   : unsigned(1 downto 0) := (others => '0');
  signal rgray, rgray_next : unsigned(1 downto 0) := (others => '0');
  signal wgray_r           : unsigned(1 downto 0);  -- wgray synced to clk_rd
  signal empty_i           : std_logic := '1';
  signal release_ok        : std_logic;

  signal ram_addr_a : std_logic_vector(G_ADDR_WIDTH downto 0);
  signal ram_addr_b : std_logic_vector(G_ADDR_WIDTH downto 0);

begin

  ------------------------------------------------------------------------------
  -- write domain: wr_commit advances the bank pointer, full = both banks
  -- committed and not yet released
  ------------------------------------------------------------------------------
  commit_ok  <= wr_commit and not full_i;
  wptr_next  <= wptr + 1 when commit_ok = '1' else wptr;
  wgray_next <= bin2gray(wptr_next);

  p_wr : process (clk_wr)
  begin
    if rising_edge(clk_wr) then
      if rst_wr = '1' then
        wptr   <= (others => '0');
        wgray  <= (others => '0');
        full_i <= '0';
      else
        wptr  <= wptr_next;
        wgray <= wgray_next;
        if wgray_next = not rgray_w then
          full_i <= '1';
        else
          full_i <= '0';
        end if;
      end if;
    end if;
  end process;

  wr_ready <= not full_i;

  ------------------------------------------------------------------------------
  -- read domain: rd_release advances the bank pointer, empty = no committed bank
  ------------------------------------------------------------------------------
  release_ok <= rd_release and not empty_i;
  rptr_next  <= rptr + 1 when release_ok = '1' else rptr;
  rgray_next <= bin2gray(rptr_next);

  p_rd : process (clk_rd)
  begin
    if rising_edge(clk_rd) then
      if rst_rd = '1' then
        rptr    <= (others => '0');
        rgray   <= (others => '0');
        empty_i <= '1';
      else
        rptr  <= rptr_next;
        rgray <= rgray_next;
        if rgray_next = wgray_r then
          empty_i <= '1';
        else
          empty_i <= '0';
        end if;
      end if;
    end if;
  end process;

  rd_valid <= not empty_i;

  ------------------------------------------------------------------------------
  -- gray pointer crossings
  ------------------------------------------------------------------------------
  gen_sync_ptr : for i in 0 to 1 generate

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
  -- storage: one dpram, MSB of the address selects the bank
  ------------------------------------------------------------------------------
  wr_ok      <= wr_en and not full_i;
  ram_addr_a <= wptr(0) & wr_addr;
  ram_addr_b <= rptr(0) & rd_addr;

  u_ram : entity work.dpram
    generic map (
      G_DATA_WIDTH => G_DATA_WIDTH,
      G_ADDR_WIDTH => G_ADDR_WIDTH + 1,
      G_OUTPUT_REG => G_OUTPUT_REG
    )
    port map (
      clk_a  => clk_wr,
      en_a   => '1',
      we_a   => wr_ok,
      addr_a => ram_addr_a,
      din_a  => wr_data,
      clk_b  => clk_rd,
      en_b   => '1',
      addr_b => ram_addr_b,
      dout_b => rd_data
    );

end architecture rtl;
