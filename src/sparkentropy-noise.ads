--  Noise sources for jitter collection.
--
--  Two sources produce CPU timing variation:
--    1. Hash loop: repeatedly runs Keccak permutation
--    2. Memory walk: pseudo-random access pattern causing cache misses
--
--  IMPORTANT: These routines MUST NOT be optimized.
--  The compiler must emit actual memory accesses and computations
--  so that timing variation is preserved.

package SPARKEntropy.Noise with
   SPARK_Mode => On,
   Elaborate_Body
is
   --  Run the hash noise source: iterate Keccak permutation.
   --  Mixes result into the sponge.
   procedure Hash_Loop
     (State : in out Entropy_State;
      Loops : Natural)
   with Post => State.Pool.Squeezed = State.Pool.Squeezed'Old;

   --  Run the memory noise source: pseudo-random walk over buffer.
   --  Uses xoshiro128** to select addresses.
   procedure Memory_Walk
     (State : in out Entropy_State;
      Loops : Natural)
   with Post => State.Pool.Squeezed = State.Pool.Squeezed'Old;

   --  Collect one jitter sample: run both noise sources,
   --  measure time delta, feed into sponge.
   --  Returns the raw time delta and whether the sample is "stuck."
   procedure Measure_Jitter
     (State : in out Entropy_State;
      Dt_Out : out U64;
      Stuck     : out Boolean)
   with Pre  => not State.Pool.Squeezed,
        Post => not State.Pool.Squeezed;

end SPARKEntropy.Noise;
