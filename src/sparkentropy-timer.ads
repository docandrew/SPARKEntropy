--  High-resolution timer for jitter measurement.
--  Uses rdtsc on x86/x86_64, clock_gettime elsewhere.

package SPARKEntropy.Timer with
   SPARK_Mode => On
is
   --  Read the current high-resolution timestamp.
   --  On x86: CPU cycle counter (rdtsc).
   --  On other platforms: clock_gettime(CLOCK_MONOTONIC) in nanoseconds.
   function Read_Timestamp return U64
   with Volatile_Function;

end SPARKEntropy.Timer;
