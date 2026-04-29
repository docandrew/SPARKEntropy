--  SPARKEntropy main package body.
--  Implements Init (power-up self-test) and Generate (random bytes).

with SPARKEntropy.Noise;
with SPARKEntropy.Health;
with SPARKEntropy.Timer;
with Keccak.Types;

package body SPARKEntropy with
   SPARK_Mode => On
is
   --  States is already use-type'd in the spec; no duplicate here.

   --================================================================
   --  Squeeze one block from a copy of the sponge
   --================================================================
   --  We extract from a COPY of the pool so the original stays in
   --  Updating state and can keep absorbing new entropy. libkeccak's
   --  Extract auto-finalizes on first call.
   procedure Squeeze_Block
     (Pool  : SHAKE.SHAKE256.Context;
      Block : out Byte_Seq)
   with Pre => SHAKE.SHAKE256.State_Of (Pool) = SHAKE.SHAKE256.Updating
               and Block'Last < Natural'Last
   is
      Copy : SHAKE.SHAKE256.Context := Pool;
      KBlock : Keccak.Types.Byte_Array (1 .. Block'Length);
   begin
      SHAKE.SHAKE256.Extract (Copy, KBlock);
      for I in Block'Range loop
         Block (I) :=
           Byte (KBlock (KBlock'First + (I - Block'First)));
      end loop;
   end Squeeze_Block;

   --================================================================
   --  GCD computation (for timer step normalization)
   --================================================================

   function GCD (A, B : U64) return U64
   with Subprogram_Variant => (Decreases => B)
   is
   begin
      if B = 0 then
         return A;
      else
         return GCD (B, A mod B);
      end if;
   end GCD;

   --================================================================
   --  Init
   --================================================================

   procedure Init
     (State : out Entropy_State;
      OK    : out Boolean)
   is
      Dt     : U64;
      Stuck  : Boolean;
      G      : U64 := 0;
      Deltas : array (0 .. Powerup_Loops - 1) of U64;
      subtype Init_Counter is Natural range 0 .. Powerup_Loops;
      Stuck_Count : Init_Counter := 0;
   begin
      --  Zero-initialize
      State := (others => <>);
      OK := False;

      --  Initialize sponge
      SHAKE.SHAKE256.Init (State.Pool);

      --  Seed xoshiro from initial timer reads
      declare
         T1 : constant U64 := Timer.Read_Timestamp;
         T2 : constant U64 := Timer.Read_Timestamp;
         T3 : constant U64 := Timer.Read_Timestamp;
      begin
         State.Xo.S0 := Unsigned_32 (T1 and 16#FFFFFFFF#);
         State.Xo.S1 := Unsigned_32 (Shift_Right (T1, 32));
         State.Xo.S2 := Unsigned_32 (T2 and 16#FFFFFFFF#);
         State.Xo.S3 := Unsigned_32 (T3 and 16#FFFFFFFF#);
         --  Ensure non-zero state
         if State.Xo.S0 = 0 and State.Xo.S1 = 0
            and State.Xo.S2 = 0 and State.Xo.S3 = 0
         then
            State.Xo.S0 := 16#DEADBEEF#;
         end if;
      end;

      --  Power-up self-test: collect 1024 samples
      --  Validates timer resolution and computes GCD
      Health.Reset_Health (State);

      for I in Deltas'Range loop
         pragma Loop_Invariant
           (SHAKE.SHAKE256.State_Of (State.Pool) =
              SHAKE.SHAKE256.Updating);
         Noise.Measure_Jitter (State, Dt, Stuck);
         Deltas (I) := Dt;
         if Stuck and then Stuck_Count < Init_Counter'Last then
            Stuck_Count := Stuck_Count + 1;
         end if;
      end loop;

      --  Check that not too many samples were stuck (< 90%)
      if Stuck_Count > (Powerup_Loops * 9) / 10 then
         return;  --  Timer too coarse or too fast
      end if;

      --  Compute GCD of all deltas
      for I in Deltas'Range loop
         if Deltas (I) > 0 then
            G := GCD (G, Deltas (I));
         end if;
      end loop;

      --  GCD too large means timer resolution is too coarse
      if G >= Unsigned_64'Last / 2 then
         return;
      end if;

      State.Timer_GCD := G;

      --  Check we have sufficient variation
      --  (sum of nonzero deltas * OSR should exceed sample count)
      declare
         Nonzero : Init_Counter := 0;
      begin
         for I in Deltas'Range loop
            if Deltas (I) > 0 and then Nonzero < Init_Counter'Last then
               Nonzero := Nonzero + 1;
            end if;
         end loop;
         if Nonzero < Powerup_Loops / 2 then
            return;  --  Insufficient variation
         end if;
      end;

      --  Reset health tests and sponge for real use
      Health.Reset_Health (State);
      SHAKE.SHAKE256.Init (State.Pool);

      State.Initialized := True;
      OK := True;
   end Init;

   --================================================================
   --  Generate
   --================================================================

   procedure Generate
     (State  : in out Entropy_State;
      Output : out Byte_Seq;
      OK     : out Boolean)
   is
      --  Number of non-stuck samples needed per 256-bit block:
      --  (256 + safety_factor) * OSR
      Samples_Per_Block : constant Natural :=
         (256 + Entropy_Safety_Factor) * State.OSR;

      Pos         : Natural := Output'First;
      Block       : Byte_Seq (0 .. Block_Size - 1);
      Good_Count  : Natural;
      Dt       : U64;
      Stuck       : Boolean;
      Health_Fail : Boolean;
   begin
      Output := (others => 0);
      OK := False;

      if not State.Initialized then
         return;
      end if;

      while Pos <= Output'Last loop
         pragma Loop_Invariant
           (SHAKE.SHAKE256.State_Of (State.Pool) =
              SHAKE.SHAKE256.Updating);
         pragma Loop_Invariant (Pos >= Output'First and Pos <= Output'Last);
         --  Collect enough non-stuck samples for one block
         Good_Count := 0;
         while Good_Count < Samples_Per_Block loop
            pragma Loop_Invariant
           (SHAKE.SHAKE256.State_Of (State.Pool) =
              SHAKE.SHAKE256.Updating);
            Noise.Measure_Jitter (State, Dt, Stuck);
            Health.Check_Health (State, Dt, Stuck, Health_Fail);

            if Health_Fail then
               return;  --  Health test failed
            end if;

            if not Stuck then
               Good_Count := Good_Count + 1;
            end if;
         end loop;

         --  Extract one block via SHAKE-256 squeeze.
         --  Copy the pool, finalize the copy, squeeze output from it.
         --  The original pool is preserved for continued absorption.
         Squeeze_Block (State.Pool, Block);

         --  Copy to output (may be partial for last block)
         declare
            Remaining : constant Natural := Output'Last - Pos + 1;
            Copy_Len  : constant Natural :=
               Natural'Min (Block_Size, Remaining);
         begin
            pragma Assert (Copy_Len <= Remaining);
            pragma Assert (Pos + Copy_Len - 1 <= Output'Last);
            Output (Pos .. Pos + Copy_Len - 1) :=
               Block (0 .. Copy_Len - 1);
            if Pos + Copy_Len > Output'Last then
               Pos := Output'Last + 1;  --  exits loop
            else
               Pos := Pos + Copy_Len;
            end if;
         end;
      end loop;

      OK := True;
   end Generate;

end SPARKEntropy;
