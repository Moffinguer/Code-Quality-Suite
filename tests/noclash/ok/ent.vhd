library ieee;
use ieee.std_logic_1164.all;
entity demo is
port (a : in std_logic; b : out std_logic);
end entity demo;
architecture rtl of demo is
begin
b <= a;
end architecture rtl;
