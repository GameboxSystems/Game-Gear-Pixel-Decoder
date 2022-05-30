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
	gg_rst      : out STD_LOGIC;
	gg_data 	: in STD_LOGIC_VECTOR(3 downto 0);
	gg_vs 		: in STD_LOGIC;
	gg_hs  		: in STD_LOGIC;
-- BRAM interface
	addra		: out STD_LOGIC_VECTOR(15 downto 0);
	dina		: out STD_LOGIC_VECTOR(11 downto 0);
	wea			: out STD_LOGIC_VECTOR( 0 downto 0)
);
end gg_decode;
---------------------------------------------------------------------------------
architecture arch_imp of gg_decode is  

-- Decoding state machine definitions
type sm_state_type is (ST_IDLE, ST_RED, ST_BLUE, ST_GREEN, ST_WRITE, ST_LEFT);
signal sm_state			: sm_state_type					:= ST_IDLE;

-- Control signal shift register definitions
signal vs_sr			: STD_LOGIC_VECTOR(2 downto 0)	:= (others => '0');
signal hs_sr			: STD_LOGIC_VECTOR(2 downto 0)	:= (others => '0');
signal clk_sr			: STD_LOGIC_VECTOR(2 downto 0)	:= (others => '0');
signal gg_clk_sr		: STD_LOGIC_VECTOR(2 downto 0)	:= (others => '0');


-- Counter definitions
signal addr_cnt			: UNSIGNED(15 downto 0)			:= (others => '0');
signal clk_cnt			: integer range 0 to 1          := 0;
signal x_cnt  			: integer range 0 to 159	    := 0;
signal y_cnt  			: integer range 0 to 145		:= 0;
signal pix_cnt  		: integer range 0 to 2   		:= 0;
signal clk_cnt_l  		: integer range 0 to 131   		:= 0;
--signal clk_cnt_r  		: integer range 0 to 79   		:= 0;

-- Intermediate signal definitions
signal gg_pix_dec 		: STD_LOGIC_VECTOR(11 downto 0) := (others => '0');
signal clk_div  		: STD_LOGIC  					:= '0';
signal clk_edge_mux     : STD_LOGIC_VECTOR(1 downto 0)  := (others => '0');
signal clk_edge_tog   	: STD_LOGIC    					:= '0';

---------------------------------------------------------------------------------
begin
---------------------------------------------------------------------------------

-- Divide ~32MHz clock down by 6 to achieve pixel clock
process(gg_clk)
begin
	if rising_edge(gg_clk) then
		--if(hs_sr(2 downto 1) = "10" or vs_sr(2 downto 1) = "01") then
		--	clk_cnt <= 0;
		--	clk_div <= not clk_div;
		--end if;
		--if(gg_clk_sr(2 downto 1) = "01") then
			if clk_cnt = 1 then
				clk_div <= not clk_div;
				clk_cnt <= 0;
			else
				clk_cnt <= clk_cnt + 1;
			end if;
		--end if;
	end if;
end process;

-- Shift register to detect signal edges
process(aclk) 
begin
	if rising_edge(aclk) then
		vs_sr 	   <= vs_sr(1 downto 0) & gg_vs; -- vsync shift reg
		hs_sr      <= hs_sr(1 downto 0) & gg_hs; -- hsync shift reg
		gg_clk_sr  <= gg_clk_sr(1 downto 0) & gg_clk; -- gg clock shift reg
		clk_sr     <= clk_sr(1 downto 0) & clk_div; 
	end if;
end process;

-- Pixel signal decoding algorithm
process(aclk)
begin
	if rising_edge(aclk) then
		case sm_state is 
			when ST_IDLE =>
				wea 						<= "0";
				gg_rst 						<= '1';
				if(vs_sr(2 downto 1) = "01") then -- If rising edge of vsync detected, start pixel decoding
					sm_state 				<= ST_LEFT;
					addr_cnt 				<= (others => '0');
					x_cnt 					<= 0;
					y_cnt 					<= 0;
					pix_cnt 				<= 0;
				elsif(hs_sr(2 downto 1) = "10" and y_cnt <= 144) then
					sm_state 				<= ST_LEFT;
					pix_cnt 				<= 0;
					x_cnt 					<= 0;
				elsif(hs_sr(2 downto 1) = "10" and y_cnt > 144) then
					sm_state 				<= ST_IDLE;
					y_cnt  					<= y_cnt + 1;
					pix_cnt 				<= 0;
					if(y_cnt = 145) then
						y_cnt  				<= 0;
					end if ;
				end if;
				if(vs_sr(2 downto 1) = "10" or vs_sr ="000") then
					sm_state 				<= ST_IDLE;
					wea 					<= "0";
				end if ;
			when ST_LEFT =>
				wea 					<= "0";
				if(clk_sr(2 downto 1) = "01") then
					clk_cnt_l  				<= clk_cnt_l + 1;
					if(clk_cnt_l = 131) then
						sm_state   			<= ST_RED;
						clk_cnt_l 			<= 0;
					end if;
				end if ;
			when ST_RED => -- First red pixel gets decoded
				wea    						<= "0";
				if (clk_sr(2 downto 1) = clk_edge_mux) then
					gg_pix_dec(11 downto 8) <= gg_data;
					sm_state 				<= ST_GREEN;
					pix_cnt 				<= pix_cnt + 1;											
				end if ;
			when ST_GREEN => -- Second is green pixel 
				wea 					<= "0";
				if(clk_sr(2 downto 1) = not clk_edge_mux) then
					gg_pix_dec(7 downto 4)  <= gg_data;
					sm_state  			    <= ST_BLUE;
					pix_cnt 				<= pix_cnt + 1;
				end if;
			when ST_BLUE => -- Third is blue pixel
				wea 					<= "0";
				if(clk_sr(2 downto 1) = clk_edge_mux) then
					gg_pix_dec(3 downto 0)  <= gg_data;
					sm_state  			    <= ST_WRITE;
					pix_cnt 				<= pix_cnt + 1;
				end if ;
			when ST_WRITE => -- then write 12 bit RGB pixel to memory/buffer for processing later
				clk_edge_tog    			<= not clk_edge_tog;
				addr_cnt  					<= addr_cnt + 1;
				x_cnt  						<= x_cnt + 1;
				addra  						<= STD_LOGIC_VECTOR(addr_cnt);
				dina   						<= gg_pix_dec;
				wea    						<= "1";
				if(x_cnt = 159) then
					sm_state   				<= ST_IDLE;
					--gg_rst 					<= '1';
					--x_cnt 					<= 0;
					--wea 					<= "0";
					--pix_cnt 				<= 0;
					--y_cnt 					<= y_cnt + 1;
					--if(y_cnt >= 145) then
					--	sm_state   				<= ST_IDLE;						
					--end if ;
				else
					sm_state   				<= ST_RED;
					gg_rst 					<= '0';
				end if;
		end case;
	end if;
end process;

clk_edge_mux <= "10" when clk_edge_tog ='0' else "01"; -- Since there is no CLKA/CLKB signals, the edges need to alternate to emulate the edges of the two different clk signals that control the pixel decoding

end arch_imp;