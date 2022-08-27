library ieee;
use ieee.std_logic_1164.all;

entity cpu_main is
	-- ST? SST? temporarily not write
	-- answer: ST SST in the charge of signals inside rather than port
	
	-- T3? what's the function of it?
	-- T3 catches falling_edge of every W1 W2 W3 goes
	port(
		CLR: in std_logic;  -- insert clr signal from outside
		T3: in std_logic;
		SW: in std_logic_vector(2 downto 0);  -- SWC SWB SWA
		W: in std_logic_vector(3 downto 1);  -- W3 W2 W1
		IR: in std_logic_vector(7 downto 4);  -- IR choose which instruction to execute
		SEL: out std_logic_vector(3 downto 0);  -- choose register to do something
		SELCTL: out std_logic;  -- determine SEL availability where SEL3~SEL2 choose register in ALU's port A and register itself, along with SEL1~SEL0 choose register in ALU's port B jointly 
		STOP: out std_logic;  -- cpu decide when to stop hence it's an "out" port
		DRW: out std_logic;  -- write register's content
		SBUS: out std_logic;  -- control data flows into bus
		LAR: out std_logic;  -- control whether data in DBUS flows into AR
		SHORT: out std_logic;  -- send out to tell time generator to produce only W1
		MBUS: out std_logic;  -- control data in memory flows to DBUS
		ARINC: out std_logic;  -- control AR's value +1 
		MEMW: out std_logic;  -- write memory from DBUS
		LIR: out std_logic;  -- load IR from INS
		PCINC: out std_logic;  -- PC's value +1
		S: out std_logic_vector(3 downto 0);  -- control ALU's calculation type
		ABUS: out std_logic;  -- control data in ALU flows to DBUS
		LDZ: out std_logic;  -- load Z=1 when result is 0
		LDC: out std_logic;  -- load C=1 when carry=1
		M: out std_logic;  -- control ALU's calculation type
		LONG: out std_logic;  -- send out to tell time generator to produce W3
		C: in std_logic;  -- get the state of C
		Z: in std_logic;  -- get the state of Z
		PCADD: out std_logic;  -- add PC's current value and data in DBUS
		LPC: out std_logic;  -- load PC from DBUS
		CIN: out std_logic  -- control ALU's calculation type
	);
end entity;

architecture arch of cpu_main is
	-- middleware signal
	-- ST0 is in charge of selecting branch of instruction
	-- ST0 doesn't change when initializing since it's controlled by SST0
	-- SST0 controls ST0
	signal ST0, SST0: std_logic := '0';
	
	-- signal W2MASK: std_logic_vector(3 downto 0);
	-- signal W3MASK: std_logic_vector(3 downto 0);
	
	-- function when SW="000"
	-- component inside by wx

begin
	process (CLR, SW, W, C, Z, IR, T3, ST0, SST0)
	begin
		-- we use T3's falling_edge to control ST since T3's cycle is shortest and matches W1 W2 W3's falling edge
		-- and there's no better choice to control ST
		
		-- initialize signals(every "out" signal)
		SEL <= "0000";
		SELCTL <= '0';
		STOP <= '0';
		DRW <= '0';
		SBUS <= '0';
		LAR <= '0';
		SHORT <= '0';
		MBUS <= '0';
		ARINC <= '0';
		MEMW <= '0';
		LIR <= '0';
		PCINC <= '0';
		S <= "0000";
		ABUS <= '0';
		LDC <= '0';
		LDZ <= '0';
		M <= '0';
		LAR <= '0';
		LONG <= '0';
		PCADD <= '0';
		LPC <= '0';
		SST0 <= '0';
		CIN <= '0';
		
		if (CLR = '0') then  -- CLR valid when low level
			-- how to express "clear" procedure?  
			-- answer: when clr we've to reconsider whether selecting instruction or not. also all out-put signals have to be reset
			-- considering after endif, all signals would be reset again, we do not have to do anything. 
			-- solved by cjh  
			ST0 <= '0';
		else 
			if (falling_edge(T3)) then
				if(SST0 = '1') then
					ST0 <= '1';
				-- cannot write else here since it changes ST0 and cannot goes into W2, when ST0 is 1 in W1
				end if;
			end if;
			if((ST0 = '1' and SW = "100" and SST0='0' and W(2)='1') or(ST0 = '1' and SW = "010" and SST0='0' and falling_edge(T3)) or (ST0 = '1' and SW = "001" and SST0='0' and falling_edge(T3))) then
				-- when read register, read/write memory, need to change ST0 to '0' after operation when ST0 = '1'.
				-- first used falling edge of W but not work because of the SW changes faster
					ST0 <= '0';
			end if;
			-- why we declare W1 W2 W3 when assigns values rather than '0' '1'?
			-- tackling the changes of W since they're sensitive signals, while '0' '1' cannot change when clock signals turn
			case SW is
				-- in the report, it should be included that why these signals here
				when "100" =>
					SBUS <= W(1) or W(2);
					-- due to initialization, every signal here only declares in high level situation
					SEL(3) <= ST0 and (W(1) or W(2));
					SEL(2) <= W(2);
					SEL(1) <= ((not ST0) and W(1)) or (ST0 and W(2));
					SEL(0) <= W(1);
					SELCTL <= W(1) or W(2);
					DRW <= W(1) or W(2);
					SST0 <= (not ST0) and W(2);
					STOP <= W(1) or W(2);
				when "011" =>
					if W(1) = '1' then
						SEL <= "0001";
					elsif W(2) = '1' then
						SEL <= "1011";
					end if;
					SELCTL <= W(1) or W(2);
					STOP <= W(1) or W(2);
				when "010" =>
					SBUS <= W(1) and (not ST0);
					LAR <= W(1) and (not ST0);
					STOP <= W(1);
					SST0 <= W(1) and (not ST0);
					SHORT <= W(1);
					SELCTL <= W(1);
					MBUS <= W(1) and ST0;
					ARINC <= W(1) and ST0;
				when "001" =>
					SBUS <= W(1);
					LAR <= W(1) and (not ST0);
					STOP <= W(1);
					SST0 <= W(1);
					SHORT <= W(1);
					SELCTL <= W(1);
					MEMW <= W(1) and ST0;
					ARINC <= W(1) and ST0;
				when "000" =>
					if ST0='0' then
						LPC <= W(1);--When ST0=0,set the following signals to 1
						SBUS <= W(1);
						SST0 <= W(1);--set SST0 to 1 so the program can execute in order 
						SHORT <= W(1);--This instruction only need W1,so set SHORT
						STOP <= W(1);--Let the user set the PC
						SELCTL <= W(1);--Set SELCTL to 1 means the operation is from the TEC-8 platform
					else	
						-- W2MASK <= W(2)&W(2)&W(2)&W(2);
						-- W3MASK <= W(3)&W(3)&W(3)&W(3);
						LIR <= W(1);
						PCINC <= W(1);
			

						-- Execute the instruction
						-- According to the IR, choose different branches to execute
						case IR is
							when "0001" =>
							-- ADD
								S <= W(2) & '0' & '0' & W(2);
								-- !!! NOT SURE IF THE ABOVE IS CORRECT !!! --
								CIN <= W(2);
								ABUS <= W(2);
								DRW <= W(2);
								LDZ <= W(2);
								LDC <= W(2);
							when "0010" =>
							-- SUB
								S <= '0' & W(2) & W(2) & '0';
								ABUS <= W(2);
								DRW <= W(2);
								LDZ <= W(2);
								LDC <= W(2);
							when "0011" =>
							-- AND
								S <= W(2) & '0' & W(2) & W(2);
								ABUS <= W(2);
								DRW <= W(2);
								LDZ <= W(2);
								M <= W(2);
							when "0100" =>
							-- INC
								S <= "0000";
								ABUS <= W(2);
								DRW <= W(2);
								LDZ <= W(2);
								LDC <= W(2);
							when "0101" =>
							-- LD
								S <= W(2) & '0' & W(2) & '0';
								M <= W(2);
								ABUS <= W(2);
								LAR <= W(2);
								LONG <= W(2);

								DRW <= W(3);
								MBUS <= W(3);
				
							when "0110" =>
							-- ST
								S <= (W(2) or W(3)) & W(2) & (W(2) or W(3)) & W(2);
								M <= W(2) or W(3);
								ABUS <= W(2) or W(3);
								LAR <= W(2);
								LONG <= W(2);
								MEMW <= W(3);
				
							when "0111" =>
							-- JC
								if C = '1' then
									PCADD <= W(2);
								end if;
				
							when "1000" =>
							-- JZ
								if Z = '1' then
									PCADD <= W(2);
								end if;
				
							when "1001" =>
							-- JMP
								S <= W(2) & W(2) & W(2) & W(2);
								M <= W(2);
								ABUS <= W(2);
								LPC <= W(2);
				
							when "1110" =>
							-- STP
								STOP <= W(2);
								
								
							--new parts
								
							when "1010" =>
							--OR
								S <= W(2) & W(2) & W(2) & '0';
								M <= W(2);
								ABUS <= W(2);
								DRW <= W(2);
								LDZ <=W(2);
							
							when "1011" =>
							--XOR
								S <= '0' & W(2) & W(2) & '0';
								M <= W(2);
								ABUS <= W(2);
								DRW <= W(2);
								LDZ <= W(2);
			
							when "1100" =>
							--DEC
								S <= W(2) & W(2) & W(2) & W(2);
								ABUS <= W(2);
								DRW <= W(2);
								LDZ <= W(2);
								LDC <= W(2);
							
							
							when others =>
							-- ILLIGAL INSTRUCTION
							-- stop the process
								STOP <= W(2);
								
							
								
						end case;
					end if;
				when others =>
					null;
			end case;
		end if;
	end process;
end architecture arch;