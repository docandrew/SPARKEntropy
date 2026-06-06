--  Timer implementation for AArch64.
--
--  Uses the architectural virtual counter. This is the one SPARK_Mode Off
--  unit in the library.

with System.Machine_Code; use System.Machine_Code;

package body SPARKEntropy.Timer with
   SPARK_Mode => Off
is

   function Read_Timestamp return U64 is
      Counter : U64;
   begin
      --  CNTVCT_EL0 is the AArch64 virtual count register.
      Asm ("mrs %0, cntvct_el0",
           Outputs  => U64'Asm_Output ("=r", Counter),
           Volatile => True);
      return Counter;
   end Read_Timestamp;

end SPARKEntropy.Timer;
