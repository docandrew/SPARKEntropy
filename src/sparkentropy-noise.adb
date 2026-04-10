--  Noise source implementation.
--
--  CRITICAL: Optimization is disabled for this entire unit.
--  The jitter entropy depends on actual CPU work being performed;
--  if the compiler optimizes away memory accesses or hash
--  computations, the timing variation disappears.

pragma Optimize (Off);

with SPARKEntropy.Keccak;
with SPARKEntropy.Timer;

package body SPARKEntropy.Noise with
   SPARK_Mode => On
is
   --================================================================
   --  xoshiro128** PRNG (for memory access randomization)
   --================================================================

   function Rotl32 (X : Unsigned_32; K : Natural) return Unsigned_32 is
     (Rotate_Left (X, K));

   procedure Xoshiro_Next (Xo : in out Xoshiro_State;
                           Val : out Unsigned_32)
   is
      Result : constant Unsigned_32 :=
         Rotl32 (Xo.S1 * 5, 7) * 9;
      T : constant Unsigned_32 := Shift_Left (Xo.S1, 9);
   begin
      Val := Result;
      Xo.S2 := Xo.S2 xor Xo.S0;
      Xo.S3 := Xo.S3 xor Xo.S1;
      Xo.S1 := Xo.S1 xor Xo.S2;
      Xo.S0 := Xo.S0 xor Xo.S3;
      Xo.S2 := Xo.S2 xor T;
      Xo.S3 := Rotl32 (Xo.S3, 11);
   end Xoshiro_Next;

   --================================================================
   --  Hash noise source
   --================================================================

   procedure Hash_Loop
     (State : in out Entropy_State;
      Loops : Natural)
   is
      --  Use a scratch Keccak state to generate timing jitter.
      --  The permutation's execution time varies with input data
      --  and CPU microarchitectural state.
      Scratch : Keccak_State := State.Pool.S;
   begin
      for I in 1 .. Loops loop
         Keccak.Permute (Scratch);
      end loop;
      --  Mix the result back (not for entropy, just to prevent
      --  dead code elimination even if pragma Optimize is ignored)
      for I in Scratch'Range loop
         State.Pool.S (I) := State.Pool.S (I) xor Scratch (I);
      end loop;
   end Hash_Loop;

   --================================================================
   --  Memory noise source
   --================================================================

   procedure Memory_Walk
     (State : in out Entropy_State;
      Loops : Natural)
   is
      Addr : Unsigned_32;
      Idx  : Natural;
   begin
      for I in 1 .. Loops loop
         --  Get pseudo-random address
         Xoshiro_Next (State.Xo, Addr);
         Idx := Natural (Addr and Unsigned_32 (Memory_Mask));

         --  Access memory at pseudo-random location.
         --  The actual value doesn't matter — it's the cache miss
         --  timing that produces jitter.
         State.Mem (Idx) := State.Mem (Idx) xor
            State.Mem ((Idx + Mem_Block_Size) mod Memory_Size);

         --  Deterministic walk as well
         State.Mem_Location :=
            (State.Mem_Location + Mem_Block_Size) mod Memory_Size;
         State.Mem (Idx) := State.Mem (Idx) xor
            State.Mem (State.Mem_Location);
      end loop;
   end Memory_Walk;

   --================================================================
   --  Measure one jitter sample
   --================================================================

   procedure Measure_Jitter
     (State : in out Entropy_State;
      Dt_Out : out U64;
      Stuck     : out Boolean)
   is
      T1, T2 : U64;
      Dt  : U64;
      Dt2 : U64;
      Dt3 : U64;
   begin
      --  Timestamp before noise sources
      T1 := Timer.Read_Timestamp;

      --  Run both noise sources
      Hash_Loop (State, Hash_Loops);
      Memory_Walk (State, Mem_Loops);

      --  Timestamp after
      T2 := Timer.Read_Timestamp;

      --  Compute time delta
      if T2 > T1 then
         Dt := T2 - T1;
      else
         --  Timer wrapped or went backwards
         Dt := T1 - T2;
      end if;

      --  Divide by GCD to remove fixed timer stepping
      if State.Timer_GCD > 1 and then Dt > 0 then
         Dt := Dt / State.Timer_GCD;
      end if;

      --  Stuck test: check 1st, 2nd, 3rd derivatives
      --  A sample is "stuck" if any derivative is zero.
      if Dt > State.Prev_Delta then
         Dt2 := Dt - State.Prev_Delta;
      else
         Dt2 := State.Prev_Delta - Dt;
      end if;

      if Dt2 > State.Prev_Delta2 then
         Dt3 := Dt2 - State.Prev_Delta2;
      else
         Dt3 := State.Prev_Delta2 - Dt2;
      end if;

      Stuck := (Dt = 0) or (Dt2 = 0) or (Dt3 = 0);

      --  Update history for next stuck test
      State.Prev_Delta2 := Dt2;
      State.Prev_Delta := Dt;
      State.Prev_Time := T2;

      --  Feed the delta into the sponge regardless of stuck status
      --  (stuck samples still provide some entropy, just not counted)
      Keccak.Absorb_U64 (State.Pool, Dt);

      Dt_Out := Dt;
   end Measure_Jitter;

end SPARKEntropy.Noise;
