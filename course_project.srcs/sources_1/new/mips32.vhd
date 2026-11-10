-- mips32.vhd : 5-stage pipelined MIPS32 core (subset ISA)
--   IF -> ID -> EX -> MEM -> WB
--   * Forwarding (EX/MEM -> EX, MEM/WB -> EX)
--   * Load-use hazard detection (1 stall cycle)
--   * Branches (beq/bne) resolved in EX, 2 wrong-path instrs flushed
--   * Jump (j) resolved in ID, 1 wrong-path instr flushed
--   * Instruction/data memories are external (async read, sync write)
-- Supported: add addu sub subu and or xor nor slt sll srl
--            addi addiu slti andi ori xori lui lw sw beq bne j
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mips_pkg.all;

entity mips32 is
  port (
    clk, rst   : in  std_logic;
    imem_addr  : out word_t;
    imem_data  : in  word_t;
    dmem_addr  : out word_t;
    dmem_wdata : out word_t;
    dmem_we    : out std_logic;
    dmem_rdata : in  word_t
  );
end entity mips32;

architecture rtl of mips32 is
  ----------------------------------------------------------------- IF
  signal pc, pc_next, pc_plus4 : word_t := ZERO32;
  ----------------------------------------------------------------- IF/ID
  signal ifid_instr : word_t := ZERO32;
  signal ifid_pc4   : word_t := ZERO32;
  ----------------------------------------------------------------- ID
  signal opcode, funct : std_logic_vector(5 downto 0);
  signal c_regwrite, c_memtoreg, c_memwrite, c_memread : std_logic;
  signal c_alusrc, c_regdst, c_beq, c_bne, c_jump, c_extzero : std_logic;
  signal c_aluop   : alu_op_t;
  signal imm_ext, rf_rd1, rf_rd2, jump_target : word_t;
  signal id_dest   : reg_addr_t;
  signal stall     : std_logic;
  ----------------------------------------------------------------- ID/EX
  signal idex_regwrite, idex_memtoreg, idex_memwrite, idex_memread : std_logic := '0';
  signal idex_alusrc, idex_beq, idex_bne : std_logic := '0';
  signal idex_aluop : alu_op_t := ALU_ADD;
  signal idex_pc4, idex_rd1, idex_rd2, idex_imm : word_t := ZERO32;
  signal idex_rs, idex_rt, idex_dest : reg_addr_t := (others => '0');
  signal idex_shamt : std_logic_vector(4 downto 0) := (others => '0');
  ----------------------------------------------------------------- EX
  signal a_fwd, b_fwd, alu_b, alu_y, branch_target : word_t;
  signal branch_taken, eq_flag : std_logic;
  ----------------------------------------------------------------- EX/MEM
  signal exmem_regwrite, exmem_memtoreg, exmem_memwrite : std_logic := '0';
  signal exmem_alu, exmem_store : word_t := ZERO32;
  signal exmem_dest : reg_addr_t := (others => '0');
  ----------------------------------------------------------------- MEM/WB
  signal memwb_regwrite, memwb_memtoreg : std_logic := '0';
  signal memwb_alu, memwb_mem : word_t := ZERO32;
  signal memwb_dest : reg_addr_t := (others => '0');
  signal wb_data : word_t;
begin
  ------------------------------------------------------------------
  -- IF stage
  ------------------------------------------------------------------
  pc_plus4  <= std_logic_vector(unsigned(pc) + 4);
  imem_addr <= pc;

  pc_next <= branch_target when branch_taken = '1' else
             pc            when stall = '1'        else
             jump_target   when c_jump = '1'       else
             pc_plus4;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then pc <= ZERO32;
      else              pc <= pc_next;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------
  -- IF/ID pipeline register
  ------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' or branch_taken = '1' then
        ifid_instr <= ZERO32;                -- flush -> NOP
        ifid_pc4   <= ZERO32;
      elsif stall = '1' then
        null;                                -- hold
      elsif c_jump = '1' then
        ifid_instr <= ZERO32;                -- squash fall-through instr
        ifid_pc4   <= ZERO32;
      else
        ifid_instr <= imem_data;
        ifid_pc4   <= pc_plus4;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------
  -- ID stage: decode, register read, hazard detection
  ------------------------------------------------------------------
  opcode <= ifid_instr(31 downto 26);
  funct  <= ifid_instr(5 downto 0);

  decode : process (opcode, funct)
  begin
    c_regwrite <= '0'; c_memtoreg <= '0'; c_memwrite <= '0'; c_memread <= '0';
    c_alusrc   <= '0'; c_regdst   <= '0'; c_beq <= '0'; c_bne <= '0';
    c_jump     <= '0'; c_extzero  <= '0'; c_aluop <= ALU_ADD;
    case opcode is
      when OP_RTYPE =>
        c_regwrite <= '1'; c_regdst <= '1';
        case funct is
          when F_SLL            => c_aluop <= ALU_SLL;
          when F_SRL            => c_aluop <= ALU_SRL;
          when F_ADD | F_ADDU   => c_aluop <= ALU_ADD;
          when F_SUB | F_SUBU   => c_aluop <= ALU_SUB;
          when F_AND            => c_aluop <= ALU_AND;
          when F_OR             => c_aluop <= ALU_OR;
          when F_XOR            => c_aluop <= ALU_XOR;
          when F_NOR            => c_aluop <= ALU_NOR;
          when F_SLT            => c_aluop <= ALU_SLT;
          when others           => c_regwrite <= '0';
        end case;
      when OP_ADDI | OP_ADDIU => c_regwrite <= '1'; c_alusrc <= '1'; c_aluop <= ALU_ADD;
      when OP_SLTI => c_regwrite <= '1'; c_alusrc <= '1'; c_aluop <= ALU_SLT;
      when OP_ANDI => c_regwrite <= '1'; c_alusrc <= '1'; c_aluop <= ALU_AND; c_extzero <= '1';
      when OP_ORI  => c_regwrite <= '1'; c_alusrc <= '1'; c_aluop <= ALU_OR;  c_extzero <= '1';
      when OP_XORI => c_regwrite <= '1'; c_alusrc <= '1'; c_aluop <= ALU_XOR; c_extzero <= '1';
      when OP_LUI  => c_regwrite <= '1'; c_alusrc <= '1'; c_aluop <= ALU_LUI;
      when OP_LW   => c_regwrite <= '1'; c_alusrc <= '1'; c_memtoreg <= '1'; c_memread <= '1';
      when OP_SW   => c_alusrc <= '1'; c_memwrite <= '1';
      when OP_BEQ  => c_beq <= '1'; c_aluop <= ALU_SUB;
      when OP_BNE  => c_bne <= '1'; c_aluop <= ALU_SUB;
      when OP_J    => c_jump <= '1';
      when others  => null;
    end case;
  end process decode;

  imm_ext <= x"0000" & ifid_instr(15 downto 0) when (c_extzero = '1' or ifid_instr(15) = '0') else
             x"FFFF" & ifid_instr(15 downto 0);

  jump_target <= ifid_pc4(31 downto 28) & ifid_instr(25 downto 0) & "00";
  id_dest     <= ifid_instr(15 downto 11) when c_regdst = '1' else ifid_instr(20 downto 16);

  rf : entity work.regfile
    port map (clk => clk, rst => rst, we => memwb_regwrite,
              ra1 => ifid_instr(25 downto 21), ra2 => ifid_instr(20 downto 16),
              wa => memwb_dest, wd => wb_data, rd1 => rf_rd1, rd2 => rf_rd2);

  -- Load-use hazard: load in EX whose destination is read by the instr in ID
  stall <= '1' when idex_memread = '1' and idex_dest /= "00000" and
                    (idex_dest = ifid_instr(25 downto 21) or
                     idex_dest = ifid_instr(20 downto 16)) else '0';

  ------------------------------------------------------------------
  -- ID/EX pipeline register
  ------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' or branch_taken = '1' or stall = '1' then
        idex_regwrite <= '0'; idex_memtoreg <= '0'; idex_memwrite <= '0';
        idex_memread  <= '0'; idex_alusrc   <= '0'; idex_beq <= '0'; idex_bne <= '0';
        idex_aluop    <= ALU_ADD;
        idex_pc4 <= ZERO32; idex_rd1 <= ZERO32; idex_rd2 <= ZERO32; idex_imm <= ZERO32;
        idex_rs <= (others => '0'); idex_rt <= (others => '0'); idex_dest <= (others => '0');
        idex_shamt <= (others => '0');
      else
        idex_regwrite <= c_regwrite; idex_memtoreg <= c_memtoreg;
        idex_memwrite <= c_memwrite; idex_memread  <= c_memread;
        idex_alusrc   <= c_alusrc;   idex_beq <= c_beq; idex_bne <= c_bne;
        idex_aluop    <= c_aluop;
        idex_pc4 <= ifid_pc4; idex_rd1 <= rf_rd1; idex_rd2 <= rf_rd2; idex_imm <= imm_ext;
        idex_rs <= ifid_instr(25 downto 21); idex_rt <= ifid_instr(20 downto 16);
        idex_dest <= id_dest; idex_shamt <= ifid_instr(10 downto 6);
      end if;
    end if;
  end process;

  ------------------------------------------------------------------
  -- EX stage: forwarding, ALU, branch resolution
  ------------------------------------------------------------------
  a_fwd <= exmem_alu when (exmem_regwrite = '1' and exmem_dest /= "00000" and exmem_dest = idex_rs) else
           wb_data   when (memwb_regwrite = '1' and memwb_dest /= "00000" and memwb_dest = idex_rs) else
           idex_rd1;

  b_fwd <= exmem_alu when (exmem_regwrite = '1' and exmem_dest /= "00000" and exmem_dest = idex_rt) else
           wb_data   when (memwb_regwrite = '1' and memwb_dest /= "00000" and memwb_dest = idex_rt) else
           idex_rd2;

  alu_b <= idex_imm when idex_alusrc = '1' else b_fwd;

  alu_i : entity work.alu
    port map (a => a_fwd, b => alu_b, shamt => idex_shamt, op => idex_aluop, y => alu_y);

  eq_flag       <= '1' when a_fwd = b_fwd else '0';
  branch_taken  <= (idex_beq and eq_flag) or (idex_bne and not eq_flag);
  branch_target <= std_logic_vector(unsigned(idex_pc4) + shift_left(unsigned(idex_imm), 2));

  ------------------------------------------------------------------
  -- EX/MEM pipeline register
  ------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        exmem_regwrite <= '0'; exmem_memtoreg <= '0'; exmem_memwrite <= '0';
        exmem_alu <= ZERO32; exmem_store <= ZERO32; exmem_dest <= (others => '0');
      else
        exmem_regwrite <= idex_regwrite; exmem_memtoreg <= idex_memtoreg;
        exmem_memwrite <= idex_memwrite;
        exmem_alu <= alu_y; exmem_store <= b_fwd; exmem_dest <= idex_dest;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------
  -- MEM stage (memory is external)
  ------------------------------------------------------------------
  dmem_addr  <= exmem_alu;
  dmem_wdata <= exmem_store;
  dmem_we    <= exmem_memwrite;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        memwb_regwrite <= '0'; memwb_memtoreg <= '0';
        memwb_alu <= ZERO32; memwb_mem <= ZERO32; memwb_dest <= (others => '0');
      else
        memwb_regwrite <= exmem_regwrite; memwb_memtoreg <= exmem_memtoreg;
        memwb_alu <= exmem_alu; memwb_mem <= dmem_rdata; memwb_dest <= exmem_dest;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------
  -- WB stage
  ------------------------------------------------------------------
  wb_data <= memwb_mem when memwb_memtoreg = '1' else memwb_alu;
end architecture rtl;
