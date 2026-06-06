--  Unsupported timer backend.

package body SPARKEntropy.Timer with
   SPARK_Mode => Off
is
   pragma Compile_Time_Error
     (True, "SPARKEntropy has no timer backend for this architecture");

   function Read_Timestamp return U64 is
   begin
      return 0;
   end Read_Timestamp;

end SPARKEntropy.Timer;
