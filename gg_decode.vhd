-------Author: Postman---------
-------Company: Gamebox--------
library ieee;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

entity gg_decode is
port(
-- gg interface
	aclk  		: in STD_LOGIC;
	gg_clk 		: in STD_LOGIC;
	gg_data 	: in STD_LOGIC_VECTOR(3 downto 0);
	gg_vs 		: in STD_LOGIC;
	gg_hs  		: in STD_LOGIC;
-- BRAM interface
	addra		: out STD_LOGIC_VECTOR(14 downto 0);
	dina		: out STD_LOGIC_VECTOR(C_BRAM_WIDTH-1 downto 0);
	wea			: out STD_LOGIC_VECTOR( 0 downto 0)
);
end gg_decode;
---------------------------------------------------------------------------------
architecture arch_imp of gg_decode is  

-- Decoding state machine definitions
type sm_state_type is (ST_IDLE, ST_RED, ST_BLUE, ST_GREEN, ST_WRITE);
signal sm_state			: sm_state_type					:= ST_IDLE;

-- Control signal shift register definitions
signal vs_sr			: STD_LOGIC_VECTOR(2 downto 0)	:= (others => '0');
signal hs_sr			: STD_LOGIC_VECTOR(2 downto 0)	:= (others => '0');
signal clk_sr			: STD_LOGIC_VECTOR(2 downto 0)	:= (others => '0');

-- Counter definitions
signal addr_cnt			: UNSIGNED(14 downto 0)			:= (others => '0');

-- Intermediate signal definitions
signal gg_pix_dec 		: STD_LOGIC_VECTOR(11 downto 0) := (others => '0');

---------------------------------------------------------------------------------
begin
---------------------------------------------------------------------------------

process(aclk) 
begin
	if rising_edge(aclk) then
		vs_sr 	<= vs_sr(2 downto 1) & gg_vs;
		hs_sr   <= hs_sr(2 downto 1) & gg_hs;
		clk_sr  <= clk_sr(2 downto 1) & gg_clk;  
	end if;
end process;

process(aclk)
begin
	if rising_edge(aclk) then
		case sm_state is 
			when ST_IDLE =>
				wea <= "0";
				if(vs_sr(2 downto 1) = "01") then
					sm_state 				<= ST_RED;
				elsif(vs_sr(2 downto 1) /= "01") then
					sm_state 				<= ST_IDLE;
					addr_cnt 				<= (others => '0');
				end if;
			when ST_RED =>
				wea    						<= "0";
				if (clk_sr(2 downto 1) = "10") then
					gg_pix_dec(11 downto 8) <= gg_data;
					sm_state 				<= ST_GREEN;
				end if ;
			when ST_GREEN =>
				if(clk_sr(2 downto 1) = "01") then
					gg_pix_dec(7 downto 4)  <= gg_data;
					sm_state  			    <= ST_BLUE;
				end if;
			when ST_BLUE =>
				if(clk_sr(2 downto 1) = "10") then
					gg_pix_dec(3 downto 0)  <= gg_data;
					sm_state  			    <= ST_WRITE;
				end if ;
			when ST_WRITE =>
				dina   						<= gg_data;
				addra  						<= STD_LOGIC_VECTOR(addr_cnt);
				addr_cnt  					<= addr_cnt + 1;
				wea  						<= "1";
				if(vs_sr(2 downto 1) = "10" or vs_sr = "000") then
					sm_state   				<= ST_IDLE;
				else
					sm_state   				<= ST_RED;
				end if ;
		end case;
	end if;
end process;

end arch_imp;