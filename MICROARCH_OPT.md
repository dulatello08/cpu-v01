# Microarchitecture Optimization Guide: Path to 50 MHz

**Target Frequency:** 50 MHz  
**Current Baseline:** ~25 MHz (Passing with 0.14ns margin)  
**Architecture:** NeoCore 16x32 (16-bit Data, 32-bit Address, Variable Length ISA, Dual-Issue)

---

## Part 1: Optimization Without Pipeline Stages (70% Focus)

Achieving a 100% frequency increase (25 MHz -> 50 MHz) without adding pipeline stages requires a relentless focus on reducing combinatorial path delays. In a 6-stage CPU like NeoCore, the critical path is almost always defined by the feedback loops in the Fetch stage (Next PC calculation) or the Hazard/Forwarding logic in the Execute stage. 

The following sections detail specific, actionable optimization strategies categorized by module.

### 1. Instruction Fetch Unit (The Primary Bottleneck)

The fetch unit currently operates on a "Zero-Wait State" mechanism where memory data is received, decoded (length only), and the next address is calculated in the *same cycle*. This creates a massive combinatorial loop: `BRAM_CLK -> BRAM_Q -> Align Shifter -> Inst Logic -> Adder -> BRAM_ADDR`. To reach 50 MHz, this loop must be slashed from ~40ns to ~20ns.

#### 1.1 Pre-Computed Next Address (Branch Prediction)
Currently, the `next_pc` is calculated *after* the instruction length is known.
*   **Optimization:** Implement a "Next Line Predictor" or a simple BTB (Branch Target Buffer) that predicts the `next_fetch_addr` based *solely* on the `current_fetch_addr` at the start of the cycle.
*   **Mechanism:**
    *   Store `predicted_target` and `is_branch` bits in a small distributed RAM indexed by PC.
    *   If prediction hits, drive `mem_addr` immediately from the predictor, bypassing the length decoding logic entirely.
    *   If prediction misses or is wrong (detected later in the cycle once length is known), assert a stall/flush and correct it (cycle penalty).
*   **Gain:** Removes the `mem_rdata -> length_decode -> adder` delay from the critical address path for the vast majority of sequential fetches.

#### 1.2 Parallel Prefix Sum for Length Calculation
We optimized `len_0` and `len_1` selection, but the adder `current_pc + len_0 + len_1` is still in the loop.
*   **Optimization:** Use a parallel prefix sum network for the 16 byte-offset lengths if scaling to wider fetch, but for 2-issue, we can optimize the adder itself.
*   **Mechanism:** Instead of adding full 32-bit `current_pc + offset`, use a 5-bit adder for the low bits to determine the BRAM index and a separate carry-generate logic. Since fetching is 16-byte aligned or close to it, the upper bits of the address rarely change. 
*   **Implementation:** `next_addr_low = current_addr_low + length`. If carry, toggle the upper bit. This is faster than a full 32-bit add.

#### 1.3 Speculative Instruction Data Forwarding
Currently, the valid signal depends on `mem_ack`. The instruction data is masked by this valid signal.
*   **Optimization:** Remove the validity mask from the data path.
*   **Mechanism:** Send *raw* data to the Decode/Issue stages constantly. Only gate the control signals (`valid_in`). This allows the logic inside Decode to settle on "garbage" data speculative (which is harmless) while the `valid` signal is resolving. When `valid` arrives late in the cycle, the data lines have already stabilized, reducing setup time violations at the next register.

#### 1.4 Hard-Coding the Alignment Mux
The `unified_memory` uses a barrel shifter to align data based on the fetch offset.
*   **Optimization:** Specialize the shifter.
*   **Mechanism:** If the FPGA architecture supports it (like Xilinx Multiplexers or Lattice PFUs), force the synthesis tool to implement the 16-byte rotator using a specific mux tree rather than a generic shifter. 
*   **Alternative:** Fetch *double* width (256 bits) from a banked arrangement in one go effectively, allowing strict subset selection without rotation logic, though this increases BRAM resource usage validity.

### 2. Unified Memory System

The unified memory creates a structural hazard and multiplexing overhead because the same physical RAMs serve two ports with complex "byte-write" logic.

#### 2.1 Pseudo-Harvard Architecture (Banking)
The Single-Port/Dual-Port arbitration logic adds delay.
*   **Optimization:** Split the BRAMs logically even if the address space is unified.
*   **Mechanism:** Use "Dual-Port" mode of BRAMs effectively. Port A is *dedicated* to Instruction Fetch (Read Only). Port B is *dedicated* to Data Access (Read/Write).
*   **Critical Detail:** Ensure that `mem_if_addr` never waits for `mem_data_addr` arbitration. They should be electrically independent paths into the BRAM hard macro.
*   **Gain:** Removes the arbitration mux from the address input of the BRAM, saving ~2-3ns.

#### 2.2 Removal of Read-Mod-Write for Sub-Word Writes
Byte writes are currently emulated or masked.
*   **Optimization:** Use the native Byte-Write Enable pins on the FPGA BRAMs.
*   **Mechanism:** ECP5 and Artix-7 BRAMs support byte-enables (data mask). Configure the `unified_memory` to wire `data_we` and `data_size` directly to these primitives.
*   **Gain:** Eliminates the need to read a word, mask it, and write it back, or complex wdata rotation logic before certain writes.

### 3. Decode Unit Efficiency

The decode unit is a large lookup table (LUT) function.

#### 3.1 Sparse Logic Encoding
The current `get_inst_length` and `opcode` tables are dense `case` statements.
*   **Optimization:** Re-map opcodes (if ISA flexibility exists) so that bit-fields directly correlate to length.
*   **Mechanism:** e.g., Bit [7] = 1 implies 4-byte instruction. Bit [6] implies Branch.
*   **Result:** The decoder becomes wires instead of logic gates. If ISA is fixed, implement a customized SOP (Sum of Products) min-term optimized specifically for the target FPGA Luts (Look-Up Tables).

#### 3.2 Parallelizing Immediate Extraction
Immediate extraction often involves sign-extending different bits based on opcode.
*   **Optimization:** Calculate ALL possible immediates in parallel.
*   **Mechanism:** `imm_type_a`, `imm_type_b`, `imm_type_c` are all computed simultaneously from `inst_data`. A final mux selects the correct one based on opcode. This is faster than a nested case statement which might synthesize to a priority encoder.

### 4. Hazard & Issue Unit

Combinatorial loops here involve: "If Inst 0 uses Reg X, and Inst 1 uses Reg X, stall Inst 1 or Forward."

#### 4.1 Bit-Vector Dependency Checking
Comparing 4-bit register addresses (`src == dst`) involves 4-bit XORs.
*   **Optimization:** Decoded "One-Hot" dependency checking.
*   **Mechanism:** Maintain a 16-bit vector `regs_being_written`.
    *   `dependency = |(src_reg_onehot & regs_being_written)`
    *   Bitwise AND reduction is often faster and maps better to wide LUT inputs than multi-bit equality comparators.

#### 4.2 Removing the "Double-Forward" Path
Forwarding from MEM -> EX and WB -> EX creates a wide mux at the ALU input.
*   **Optimization:** Collapse forwarding muxes.
*   **Mechanism:** Instead of a 3:1 Mux (RegFile, Forward_MEM, Forward_WB) at the ALU input, pre-calculate the operand in the ID/EX pipeline register latch phase if possible, OR move the mux to the very end of the previous stage (unconventional but sometimes effective on FPGAs with fast routing).
*   **Better Approach:** Critical Path is usually `ALU_Op -> ALU_Result`. The forwarding Mux adds to this. Ensure the `Forward_Select` signal is computed *early* in the ID stage so the Mux select line is stable before the data arrives.

---

## Part 2: Optimization WITH Pipeline Stages (30% Focus)

If 50 MHz cannot be reached via pure combinatorial optimization (or if the goal shifts to 100 MHz+), pipeline stages effectively "cut" the long paths. The trade-off is IPC (Instructions Per Cycle) due to increased branch penalties and load-use latencies.

### 1. The "Fetch" Pipeline Split (2-Stage Fetch)

The single biggest gain comes from splitting Fetch.

**Current:** `Address -> Memory -> Data -> Align -> Next Address` (1 Cycle)
**New:** `Address -> Memory` (Cycle 1) -> `Data -> Align -> Next Address` (Cycle 2)

#### 1.1 F1: Address Generation
This stage creates the `fetch_addr`. It contains the PC register, the Branch Predictor (BTB), and the Mux selecting between `PC+4`, `Branch_Target`, or `Return_Stack`.
*   **Benefit:** The critical path is just the Mux + Register Setup. Very fast (>100 MHz easy).

#### 1.2 F2: Instruction Memory Access
The address from F1 drives the BRAM. The data comes out and is latched into the `F2/D` pipeline register.
*   **Benefit:** This stage contains the full BRAM access time (~10-15ns on slow FPGAs, ~3-4ns on fast ones). It is isolated from the logic of decoding.

#### 1.3 F3: Alignment & Pre-Decode (The "Queue" Stage)
Raw 128-bit data from Memory is aligned, parsed for length, and pushed into a **Fetch Queue (FIFO)**.
*   **Benefit:** By decoupling Fetch from Decode with a FIFO, the Fetch unit can run ahead of the rest of the CPU. If the Decode unit stalls (complex instruction), the Fetch unit keeps filling the queue.
*   **Critical Enablement:** This hides the variable-length instruction penalty. The "Alignment Shifter" becomes the critical path of this stage, but it no longer loops back to the Address Generation immediately (only via FIFO full flags).

### 2. The "Register Read" Stage (Decouple ID)

Current `Decode` does both "Figure out what to do" and "Fetch operands from Register File".
*   **New Pipeline:** `IF -> ID (Decode Control) -> RF (Read Regs) -> EX -> ...`
*   **Logic:**
    *   **ID:** Decodes Opcode, Generates Immediate, Calculates Branch Target, Checks Dependencies.
    *   **RF:** Reads the Register File array.
*   **Benefit:** Register Files (especially larger ones) can be slow. Separating the read allows the `Control Logic` (Hazard Unit) to calculate stall signals a full cycle earlier, relaxing timing constraints significantly.

### 3. Memory Access Split (AGU vs Cache)

**Current:** `Addr Calc -> Mem Access` in one EX/MEM transition.
**New:**
*   **EX:** Calculates Address (`Base + Offset`).
*   **MEM1:** Sends Address to Memory / Tag Check.
*   **MEM2:** Data returns.
*   **Benefit:** Essential for higher speeds where SRAM access time + wire delay exceeds the cycle time.

### 4. Summary of Pipelined Architecture (Super-NeoCore)

To hit 50-100 MHz comfortably:

1.  **F1 (Fetch 1):** PC Gen / BTB Access
2.  **F2 (Fetch 2):** I-Cache / BRAM Access
3.  **PD (Pre-Decode):** Length Decode / Align / Push to Queue
4.  **ID (Decode):** Pop Queue / Decode Control / Dependency Check
5.  **RR (Reg Read):** Read Register File
6.  **EX (Execute):** ALU / Shift / Mult
7.  **MEM (Memory):** D-Cache / BRAM Access
8.  **WB (Writeback):** Write Register File

**Total:** 8 Stages.
**Impact:** Simple operations now take 8 cycles latency, so Branch Prediction becomes *mandatory*. Without it, a branch misprediction costs 8 cycles, destroying performance. However, frequency can easily double or triple.

---

## Conclusion & Recommendation

For the target of 50 MHz, the full 8-stage pipeline is overkill and introduces too much complexity (hazards, flushing logic).

**Recommended Path:**
1.  **Stay with 6 stages.**
2.  **Implement the "Pseudo-Parallel" Fetch optimizations** (Part 1.2 and 1.3).
3.  **Harden the BRAM Macros** (Part 2.1) to ensure dedicated ports.
4.  **Rewrite Hazard Logic** to use bit-vectors (Part 4.1).
5.  **Only if 50 MHz fails:** Add **one** pipeline stage between Fetch and Decode (The "Fetch Queue"). This decouples the memory latency from the decoding logic, which is the single tightest knot in the design.
