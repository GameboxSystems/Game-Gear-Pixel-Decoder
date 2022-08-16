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
	gg_sms  	: in STD_LOGIC;
-- FIFO interface
	m_axis_tvalid  	: out STD_LOGIC;
	m_axis_tuser    : out STD_LOGIC_VECTOR( 1 downto 0)	:= (others => '0');
	m_axis_tdata    : out STD_LOGIC_VECTOR(31 downto 0)	:= (others => '0');
	m_axis_tlast    : out STD_LOGIC;
-- Counters out
	x_cnt_out 			: out UNSIGNED(7 downto 0);
	y_cnt_out  			: out UNSIGNED(7 downto 0);
-- Filter interface
	filt_data_drv       : out STD_LOGIC := '0'
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
signal x_cnt_limit		: integer	    				:= 0; --sms = 0 => 159, sms = 1 => 255
signal x_cnt  			: integer	    				:= 0;
signal y_cnt_limit		: integer 						:= 0; --sms = 0 => 143, sms = 1 => 191
signal y_cnt  			: integer 						:= 0; 
signal pix_cnt  		: integer 				   		:= 0;
signal clk_cnt_l_limit	: integer 				   		:= 0; --sms = 1 => 65, sms = 0 => 131
signal clk_cnt_l  		: integer 				   		:= 0; 
--signal clk_cnt_r  		: integer range 0 to 79   		:= 0;

-- Intermediate signal definitions
signal gg_pix_dec 		: STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
signal clk_div  		: STD_LOGIC  					:= '0';
signal clk_edge_mux     : STD_LOGIC_VECTOR(1 downto 0)  := (others => '0');
signal clk_edge_tog   	: STD_LOGIC    					:= '0';
signal valid_drv		: STD_LOGIC;
signal user_drv			: STD_LOGIC;
signal last_drv			: STD_LOGIC;
signal filt_data        : STD_LOGIC;

---------------------------------------------------------------------------------
begin
---------------------------------------------------------------------------------

-- Divide ~32MHz clock down by 6 to achieve pixel clock
process(aclk)
begin
	if rising_edge(aclk) then
		if(hs_sr(2 downto 1) = "10" or vs_sr(2 downto 1) = "01") then
			clk_cnt <= 1;
			clk_div <= '1';
		end if;
		if(gg_clk_sr(2 downto 1) = "01") then
			if clk_cnt = 1 then
				clk_div <= not clk_div;
				clk_cnt <= 0;
			else
				clk_cnt <= clk_cnt + 1;
			end if;
		end if;
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
				user_drv				<= '0';
				last_drv				<= '0';
				valid_drv				<= '0';
				filt_data 				<= '0';
				if(vs_sr(2 downto 1) = "01") then -- If rising edge of vsync detected, start pixel decoding
					sm_state 				<= ST_LEFT;
					x_cnt 					<= 0;
					y_cnt 					<= 0;
					user_drv				<= '1';
					last_drv				<= '0';
					valid_drv				<= '1';
					--clk_edge_tog 			<= '0';
				elsif(hs_sr(2 downto 1) = "10" and (vs_sr(2 downto 1) = "01" or vs_sr(2 downto 1) = "11")) then
					user_drv				<= '0';
					last_drv				<= '1';
					if (y_cnt > 8 and gg_sms = '1') or gg_sms = '0' then
						valid_drv				<= '1';
					else
						valid_drv 				<= '0';
					end if ;
					x_cnt 					<= 0;
					sm_state 				<= ST_LEFT;
				elsif(vs_sr(2 downto 1) = "10" or vs_sr ="000") then
					sm_state 				<= ST_IDLE;
				end if ;
			when ST_LEFT =>
				user_drv				<= '0';
				last_drv				<= '0';
				valid_drv				<= '0';
				if(clk_sr(2 downto 1) = "01") then
					clk_cnt_l  				<= clk_cnt_l + 1;
					if(clk_cnt_l = clk_cnt_l_limit) then
						sm_state   			<= ST_RED;
						--clk_edge_tog    	<= not clk_edge_tog;
						clk_cnt_l 			<= 0;
					end if;
				end if ;
			when ST_RED => -- First red pixel gets decoded
				user_drv				<= '0';
				last_drv				<= '0';
				valid_drv				<= '0';
				filt_data 	    		<= '0';
				if (clk_sr(2 downto 1) = clk_edge_mux) then
					gg_pix_dec(11 downto 8) <= gg_data;
					sm_state 				<= ST_GREEN;
					pix_cnt 				<= pix_cnt + 1;											
				end if ;
			when ST_GREEN => -- Second is green pixel 
				user_drv				<= '0';
				last_drv				<= '0';
				valid_drv				<= '0';
				if(clk_sr(2 downto 1) = not clk_edge_mux) then
					gg_pix_dec(7 downto 4)  <= gg_data;
					sm_state  			    <= ST_BLUE;
					pix_cnt 				<= pix_cnt + 1;
				end if;
			when ST_BLUE => -- Third is blue pixel
				user_drv				<= '0';
				last_drv				<= '0';
				valid_drv				<= '0';
				if(clk_sr(2 downto 1) = clk_edge_mux) then
					gg_pix_dec(3 downto 0)  <= gg_data;
					sm_state  			    <= ST_WRITE;
					pix_cnt 				<= pix_cnt + 1;
				end if ;
			when ST_WRITE => -- then write 12 bit RGB pixel to memory/buffer for processing later
				user_drv				<= '0';
				last_drv				<= '0';
				valid_drv				<= '1';
				filt_data 	    		<= '1';
				clk_edge_tog    			<= not clk_edge_tog;
				--addr_cnt  					<= addr_cnt + 1;
				--addra  						<= STD_LOGIC_VECTOR(addr_cnt);
				--if (y_cnt > 8 and gg_sms = '1') or gg_sms = '0' then
					m_axis_tdata   						<= gg_pix_dec;
				--	user_drv				<= '0';
				--	last_drv				<= '0';
				--	valid_drv				<= '1';
				--end if ;
				if(x_cnt = x_cnt_limit) then
					sm_state   				<= ST_IDLE;
					--gg_rst 					<= '1';
					--x_cnt 					<= 0;
					--wea 					<= "0";
					--pix_cnt 				<= 0;
					--filt_data 	    		<= '0';
					y_cnt 					<= y_cnt + 1;
					--if(y_cnt >= 145) then
					--	sm_state   				<= ST_IDLE;						
					--end if ;
				else
					sm_state   				<= ST_RED;
					x_cnt  						<= x_cnt + 1;
				end if;
		end case;
	end if;
end process;

x_cnt_limit       <= 159 when gg_sms = '0' else
					 255 when gg_sms = '1';
y_cnt_limit 	  <= 143 when gg_sms = '0' else 
					 191 when gg_sms = '1';
clk_cnt_l_limit   <= 132 when gg_sms = '0' else
					 65  when gg_sms = '1';

x_cnt_out  		<= TO_UNSIGNED(x_cnt,8);
y_cnt_out  		<= TO_UNSIGNED(y_cnt,8);

m_axis_tvalid		<= valid_drv;
m_axis_tuser(0)		<= user_drv;
m_axis_tlast		<= last_drv;

filt_data_drv       <= filt_data;

clk_edge_mux <= "10" when clk_edge_tog ='0' else "01"; -- Since there is no CLKA/CLKB signals, the edges need to alternate to emulate the edges of the two different clk signals that control the pixel decoding

end arch_imp;