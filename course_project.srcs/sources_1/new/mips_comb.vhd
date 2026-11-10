-- mips_comb.vhd : the MIPS32 pipeline expressed as pure combinational logic.
-- next_state = f(state, imem_data, dmem_rdata).  All registers live in the
-- flat 'state' vector (layout in mips_pkg), so the scan wrapper can make
-- every one of them a scan cell.  Logic is identical to mips32.vhd.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mips_pkg.all;

entity mips_comb is
  port (
    rst        : in  std_logic;
    state      : in  std_logic_vector(STATE_W-1 downto 0);
    imem_data  : in  word_t;
    dmem_rdata : in  word_t;
    next_state : out std_logic_vector(STATE_W-1 downto 0);
    imem_addr  : out word_t;
    dmem_addr  : out word_t;
    dmem_wdata : out word_t;
    dmem_we    : out std_logic
  );
end entity mips_comb;

architecture rtl of mips_comb is
  type reg_array_t is array (0 to 31) of word_t;
  signal rf : reg_array_t;

  -- unpacked current state
  signal pc, ifid_instr, ifid_pc4 : word_t;
  signal idex_regwrite, idex_memtoreg, idex_memwrite, idex_memread : std_logic;
  signal idex_alusrc, idex_beq, idex_bne : std_logic;
  signal idex_aluop : alu_op_t;
  signal idex_pc4, idex_rd1, idex_rd2, idex_imm : word_t;
  signal idex_rs, idex_rt, idex_dest : reg_addr_t;
  signal idex_shamt : std_logic_vector(4 downto 0);
  signal exmem_regwrite, exmem_memtoreg, exmem_memwrite : std_logic;
  signal exmem_alu, exmem_store : word_t;
  signal exmem_dest : reg_addr_t;
  signal memwb_regwrite, memwb_memtoreg : std_logic;
  signal memwb_alu, memwb_mem : word_t;
  signal memwb_dest : reg_addr_t;

  -- combinational signals
  signal pc_plus4, pc_next, jump_target, imm_ext, rf_rd1, rf_rd2 : word_t;
  signal opcode, funct : std_logic_vector(5 downto 0);
  signal c_regwrite, c_memtoreg, c_memwrite, c_memread : std_logic;
  signal c_alusrc, c_regdst, c_beq, c_bne, c_jump, c_extzero : std_logic;
  signal c_aluop : alu_op_t;
  signal id_dest : reg_addr_t;
  signal stall, flush_idex : std_logic;
  signal a_fwd, b_fwd, alu_b, alu_y, branch_target, wb_data : word_t;
  signal branch_taken, eq_flag : std_logic;
  signal ns : std_logic_vector(STATE_W-1 downto 0);
begin
  ---------------------------------------------------------------- unpack
  pc            <= state(S_PC+31 downto S_PC);
  ifid_instr    <= state(S_IFID_INSTR+31 downto S_IFID_INSTR);
  ifid_pc4      <= state(S_IFID_PC4+31 downto S_IFID_PC4);
  idex_regwrite <= state(S_IDEX_RW);
  idex_memtoreg <= state(S_IDEX_M2R);
  idex_memwrite <= state(S_IDEX_MW);
  idex_memread  <= state(S_IDEX_MR);
  idex_alusrc   <= state(S_IDEX_SRC);
  idex_beq      <= state(S_IDEX_BEQ);
  idex_bne      <= state(S_IDEX_BNE);
  idex_aluop    <= state(S_IDEX_ALUOP+3 downto S_IDEX_ALUOP);
  idex_pc4      <= state(S_IDEX_PC4+31 downto S_IDEX_PC4);
  idex_rd1      <= state(S_IDEX_RD1+31 downto S_IDEX_RD1);
  idex_rd2      <= state(S_IDEX_RD2+31 downto S_IDEX_RD2);
  idex_imm      <= state(S_IDEX_IMM+31 downto S_IDEX_IMM);
  idex_rs       <= state(S_IDEX_RS+4 downto S_IDEX_RS);
  idex_rt       <= state(S_IDEX_RT+4 downto S_IDEX_RT);
  idex_dest     <= state(S_IDEX_DEST+4 downto S_IDEX_DEST);
  idex_shamt    <= state(S_IDEX_SH+4 downto S_IDEX_SH);
  exmem_regwrite<= state(S_EXMEM_RW);
  exmem_memtoreg<= state(S_EXMEM_M2R);
  exmem_memwrite<= state(S_EXMEM_MW);
  exmem_alu     <= state(S_EXMEM_ALU+31 downto S_EXMEM_ALU);
  exmem_store   <= state(S_EXMEM_ST+31 downto S_EXMEM_ST);
  exmem_dest    <= state(S_EXMEM_DEST+4 downto S_EXMEM_DEST);
  memwb_regwrite<= state(S_MEMWB_RW);
  memwb_memtoreg<= state(S_MEMWB_M2R);
  memwb_alu     <= state(S_MEMWB_ALU+31 downto S_MEMWB_ALU);
  memwb_mem     <= state(S_MEMWB_MEM+31 downto S_MEMWB_MEM);
  memwb_dest    <= state(S_MEMWB_DEST+4 downto S_MEMWB_DEST);

  rf(0) <= ZERO32;
  gen_rf : for k in 1 to 31 generate
    rf(k) <= state(S_REGS+(k-1)*32+31 downto S_REGS+(k-1)*32);
  end generate gen_rf;

  ---------------------------------------------------------------- outputs
  imem_addr  <= pc;
  dmem_addr  <= exmem_alu;
  dmem_wdata <= exmem_store;
  dmem_we    <= exmem_memwrite;

  ---------------------------------------------------------------- IF
  pc_plus4 <= std_logic_vector(unsigned(pc) + 4);
  pc_next  <= branch_target when branch_taken = '1' else
              pc            when stall = '1'        else
              jump_target   when c_jump = '1'       else
              pc_plus4;

  ---------------------------------------------------------------- ID
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

  -- register read with write-through from WB
  rf_rd1 <= ZERO32 when ifid_instr(25 downto 21) = "00000" else
            wb_data when (memwb_regwrite = '1' and memwb_dest = ifid_instr(25 downto 21)) else
            rf(to_integer(unsigned(ifid_instr(25 downto 21))));
  rf_rd2 <= ZERO32 when ifid_instr(20 downto 16) = "00000" else
            wb_data when (memwb_regwrite = '1' and memwb_dest = ifid_instr(20 downto 16)) else
            rf(to_integer(unsigned(ifid_instr(20 downto 16))));

  stall <= '1' when idex_memread = '1' and idex_dest /= "00000" and
                    (idex_dest = ifid_instr(25 downto 21) or
                     idex_dest = ifid_instr(20 downto 16)) else '0';
  flush_idex <= branch_taken or stall;

  ---------------------------------------------------------------- EX
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

  ---------------------------------------------------------------- WB
  wb_data <= memwb_mem when memwb_memtoreg = '1' else memwb_alu;

  ---------------------------------------------------------------- next state
  ns(S_PC+31 downto S_PC) <= pc_next;

  ns(S_IFID_INSTR+31 downto S_IFID_INSTR) <=
        ZERO32 when branch_taken = '1' else
        ifid_instr when stall = '1' else
        ZERO32 when c_jump = '1' else imem_data;
  ns(S_IFID_PC4+31 downto S_IFID_PC4) <=
        ZERO32 when branch_taken = '1' else
        ifid_pc4 when stall = '1' else
        ZERO32 when c_jump = '1' else pc_plus4;

  ns(S_IDEX_RW)  <= '0' when flush_idex = '1' else c_regwrite;
  ns(S_IDEX_M2R) <= '0' when flush_idex = '1' else c_memtoreg;
  ns(S_IDEX_MW)  <= '0' when flush_idex = '1' else c_memwrite;
  ns(S_IDEX_MR)  <= '0' when flush_idex = '1' else c_memread;
  ns(S_IDEX_SRC) <= '0' when flush_idex = '1' else c_alusrc;
  ns(S_IDEX_BEQ) <= '0' when flush_idex = '1' else c_beq;
  ns(S_IDEX_BNE) <= '0' when flush_idex = '1' else c_bne;
  ns(S_IDEX_ALUOP+3 downto S_IDEX_ALUOP) <= ALU_ADD when flush_idex = '1' else c_aluop;
  ns(S_IDEX_PC4+31 downto S_IDEX_PC4) <= ZERO32 when flush_idex = '1' else ifid_pc4;
  ns(S_IDEX_RD1+31 downto S_IDEX_RD1) <= ZERO32 when flush_idex = '1' else rf_rd1;
  ns(S_IDEX_RD2+31 downto S_IDEX_RD2) <= ZERO32 when flush_idex = '1' else rf_rd2;
  ns(S_IDEX_IMM+31 downto S_IDEX_IMM) <= ZERO32 when flush_idex = '1' else imm_ext;
  ns(S_IDEX_RS+4 downto S_IDEX_RS)     <= "00000" when flush_idex = '1' else ifid_instr(25 downto 21);
  ns(S_IDEX_RT+4 downto S_IDEX_RT)     <= "00000" when flush_idex = '1' else ifid_instr(20 downto 16);
  ns(S_IDEX_DEST+4 downto S_IDEX_DEST) <= "00000" when flush_idex = '1' else id_dest;
  ns(S_IDEX_SH+4 downto S_IDEX_SH)     <= "00000" when flush_idex = '1' else ifid_instr(10 downto 6);

  ns(S_EXMEM_RW)  <= idex_regwrite;
  ns(S_EXMEM_M2R) <= idex_memtoreg;
  ns(S_EXMEM_MW)  <= idex_memwrite;
  ns(S_EXMEM_ALU+31 downto S_EXMEM_ALU) <= alu_y;
  ns(S_EXMEM_ST+31 downto S_EXMEM_ST)   <= b_fwd;
  ns(S_EXMEM_DEST+4 downto S_EXMEM_DEST) <= idex_dest;

  ns(S_MEMWB_RW)  <= exmem_regwrite;
  ns(S_MEMWB_M2R) <= exmem_memtoreg;
  ns(S_MEMWB_ALU+31 downto S_MEMWB_ALU) <= exmem_alu;
  ns(S_MEMWB_MEM+31 downto S_MEMWB_MEM) <= dmem_rdata;
  ns(S_MEMWB_DEST+4 downto S_MEMWB_DEST) <= exmem_dest;

  gen_ns_rf : for k in 1 to 31 generate
    ns(S_REGS+(k-1)*32+31 downto S_REGS+(k-1)*32) <=
        wb_data when (memwb_regwrite = '1' and to_integer(unsigned(memwb_dest)) = k)
        else state(S_REGS+(k-1)*32+31 downto S_REGS+(k-1)*32);
  end generate gen_ns_rf;

  next_state <= (others => '0') when rst = '1' else ns;
end architecture rtl;
