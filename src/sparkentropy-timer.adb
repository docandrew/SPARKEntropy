--  Timer implementation.
--
--  x86/x86_64: uses rdtsc via inline assembly.
--  This is the one SPARK_Mode Off unit in the library.

with System.Machine_Code; use System.Machine_Code;
with Interfaces; use Interfaces;

package body SPARKEntropy.Timer with
   SPARK_Mode => Off
is

   function Read_Timestamp return U64 is
      Lo, Hi : Unsigned_32;
   begin
      --  rdtsc: returns cycle count in EDX:EAX
      Asm ("rdtsc",
           Outputs  => (Unsigned_32'Asm_Output ("=a", Lo),
                        Unsigned_32'Asm_Output ("=d", Hi)),
           Volatile => True);
      return Shift_Left (U64 (Hi), 32) or U64 (Lo);
   end Read_Timestamp;

end SPARKEntropy.Timer;
