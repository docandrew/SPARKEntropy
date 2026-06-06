--  High-resolution timer for jitter measurement.
--  Current implementations use rdtsc on x86/x86_64 and CNTVCT_EL0 on
--  AArch64.

package SPARKEntropy.Timer with
   SPARK_Mode => On
is
   --  Read the current high-resolution timestamp.
   --  On x86: CPU cycle counter (rdtsc).
   --  On AArch64: architectural virtual counter (CNTVCT_EL0).
   function Read_Timestamp return U64
   with Volatile_Function;

end SPARKEntropy.Timer;
