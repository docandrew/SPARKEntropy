--  Noise sources for jitter collection.
--
--  Two sources produce CPU timing variation:
--    1. Hash loop: repeatedly runs Keccak permutation on Jitter_State
--    2. Memory walk: pseudo-random access pattern causing cache misses
--
--  IMPORTANT: These routines MUST NOT be optimized.
--  The compiler must emit actual memory accesses and computations
--  so that timing variation is preserved.

--  SHAKE.SHAKE256.States is already use-type'd at the parent level
--  (SPARKEntropy.ads); no separate import needed here.

package SPARKEntropy.Noise with
   SPARK_Mode => On,
   Elaborate_Body
is

   --  Run the hash noise source: iterate Keccak permutation on the
   --  raw Jitter_State (NOT the cryptographic Pool).
   procedure Hash_Loop
     (State : in out Entropy_State;
      Loops : Natural)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool'Old);

   --  Run the memory noise source: pseudo-random walk over buffer.
   --  Uses xoshiro128** to select addresses.
   procedure Memory_Walk
     (State : in out Entropy_State;
      Loops : Natural)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool'Old);

   --  Collect one jitter sample: run both noise sources,
   --  measure time delta, feed into sponge.
   --  Returns the raw time delta and whether the sample is "stuck."
   procedure Measure_Jitter
     (State : in out Entropy_State;
      Dt_Out : out U64;
      Stuck     : out Boolean)
   with Pre  => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.Updating,
        Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.Updating;

end SPARKEntropy.Noise;
