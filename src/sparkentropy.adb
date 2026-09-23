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

   ----------------------------------------------------------------------------
   --  Squeeze one block from a copy of the sponge
   ----------------------------------------------------------------------------
   --  We extract from a COPY of the pool so the original stays in
   --  Updating state and can keep absorbing new entropy. libkeccak's
   --  Extract auto-finalizes on first call.
   procedure Squeeze_Block
     (Pool  : SHAKE.SHAKE256.Context;
      Block : out Byte_Seq)
   with Pre => SHAKE.SHAKE256.State_Of (Pool) = SHAKE.SHAKE256.Updating
               --  The single caller (Generate) passes a 32-byte
               --  fixed buffer. We bound the length here so the
               --  prover can show the local KBlock array index
               --  expression `1 .. Block'Length` fits inside
               --  Keccak.Types.Index_Number (0 .. Natural'Last - 1).
               and Block'Length <= 1024
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

   ----------------------------------------------------------------------------
   --  GCD computation (for timer step normalization)
   ----------------------------------------------------------------------------

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

   ----------------------------------------------------------------------------
   --  Init
   ----------------------------------------------------------------------------

   procedure Init
     (State : in out Entropy_State;
      OK    : out Boolean;
      OSR   : OSR_Range := Min_OSR)
   is
      Dt     : U64;
      Stuck  : Boolean;
      G      : U64 := 0;
      Deltas : array (0 .. Powerup_Loops - 1) of U64 := (others => 0);
      subtype Init_Counter is Natural range 0 .. Powerup_Loops;
      Stuck_Count : Init_Counter := 0;
      Status : Health_Status;
      Retest : Boolean;
      --  Start-up retries left (one per oversampling rate up to Max_OSR);
      --  the loop variant, kept apart from State so callees cannot
      --  disturb it.
      Retries : Natural range 0 .. Max_OSR - Min_OSR := Max_OSR - OSR;
   begin
      --  State arrives default-initialized (every field has a
      --  declared default in the Entropy_State record); we update
      --  individual fields below rather than re-aggregating with
      --  (others => <>) which SPARK forbids.
      OK := False;
      State.Initialized := False;
      State.OSR := OSR;   --  before Reset_Health: the cutoffs scale with it
      State.Last_Health := Healthy;

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

      --  Power-up self-test: collect 1024 samples under the health tests.
      --  Validates timer resolution and computes the GCD. An intermittent
      --  health failure here is retried at the next oversampling rate,
      --  as jitterentropy's start-up does; a permanent one, or reaching
      --  Max_OSR, fails Init.
      loop
         pragma Loop_Invariant
           (SHAKE.SHAKE256.State_Of (State.Pool) =
              SHAKE.SHAKE256.Updating);
         pragma Loop_Variant (Decreases => Retries);
         Health.Reset_Health (State);
         Stuck_Count := 0;
         Retest := False;
         for I in Deltas'Range loop
            pragma Loop_Invariant
              (SHAKE.SHAKE256.State_Of (State.Pool) =
                 SHAKE.SHAKE256.Updating);
            Noise.Measure_Jitter (State, Dt, Stuck);
            Health.Check_Health (State, Dt, Stuck, Status);
            if Status = Permanent then
               State.Last_Health := Permanent;
               return;
            elsif Status = Intermittent then
               Retest := True;
               exit;
            end if;
            Deltas (I) := Dt;
            if Stuck and then Stuck_Count < Init_Counter'Last then
               Stuck_Count := Stuck_Count + 1;
            end if;
         end loop;
         exit when not Retest;
         if Retries = 0 or else State.OSR = Max_OSR then
            State.Last_Health := Permanent;
            return;
         end if;
         Retries := Retries - 1;
         State.OSR := State.OSR + 1;
         if State.Resets < Natural'Last then
            State.Resets := State.Resets + 1;
         end if;
         State.Last_Health := Intermittent;
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

   ----------------------------------------------------------------------------
   --  Generate
   ----------------------------------------------------------------------------

   procedure Generate
     (State  : in out Entropy_State;
      Output : out Byte_Seq;
      OK     : out Boolean)
   is
      Pos         : Natural;
      Block       : Byte_Seq (0 .. Block_Size - 1);
      Good_Count  : Natural;
      Dt          : U64;
      Stuck       : Boolean;
      Status      : Health_Status;
      Restart     : Boolean;
      Recovered   : Boolean := False;
      Init_OK     : Boolean;
      --  Recoveries left in this request: one. The loop variant; the
      --  ghost snapshot lets the inner loops state how it moved.
      Budget       : Natural range 0 .. 1 := 1;
      Budget_Start : Natural range 0 .. 1 := 1 with Ghost;

      --  Latch the generator off: nothing is handed back, and only a new
      --  Init brings it back.
      procedure Latch_Off is
      begin
         Output := (others => 0);
         State.Initialized := False;
         State.Last_Health := Permanent;
      end Latch_Off;
   begin
      Output := (others => 0);
      OK := False;

      if not State.Initialized then
         return;
      end if;

      --  The request runs at most twice: once more after an intermittent
      --  health failure has been recovered from.
      loop
         pragma Loop_Invariant
           (SHAKE.SHAKE256.State_Of (State.Pool) =
              SHAKE.SHAKE256.Updating);
         pragma Loop_Variant (Decreases => Budget);
         Restart := False;
         Budget_Start := Budget;
         Pos := Output'First;
         Output := (others => 0);

         while Pos <= Output'Last and then not Restart loop
            pragma Loop_Invariant
              (SHAKE.SHAKE256.State_Of (State.Pool) =
                 SHAKE.SHAKE256.Updating);
            pragma Loop_Invariant (Pos >= Output'First and Pos <= Output'Last);
            pragma Loop_Invariant (not Restart and Budget = Budget_Start);

            --  Collect enough non-stuck samples for one block:
            --  (256 + safety_factor) * OSR, read from State because a
            --  recovery raises the rate.
            Good_Count := 0;
            while Good_Count < (256 + Entropy_Safety_Factor) * State.OSR
              and then not Restart
            loop
               pragma Loop_Invariant
                 (SHAKE.SHAKE256.State_Of (State.Pool) =
                    SHAKE.SHAKE256.Updating);
               pragma Loop_Invariant (not Restart and Budget = Budget_Start);
               Noise.Measure_Jitter (State, Dt, Stuck);
               Health.Check_Health (State, Dt, Stuck, Status);

               case Status is
                  when Healthy =>
                     if not Stuck then
                        Good_Count := Good_Count + 1;
                     end if;

                  when Intermittent =>
                     --  SP 800-90B 4.3 intermittent failure (alpha 2^-30,
                     --  expected now and then from a healthy source): as
                     --  jitterentropy's reset does, discard the pool,
                     --  re-run the start-up tests at the next oversampling
                     --  rate, and start the request over. A second one in
                     --  the same request, a rate already at Max_OSR, or a
                     --  failed retest is treated as permanent.
                     if Recovered or else Budget = 0 or else State.OSR = Max_OSR then
                        Latch_Off;
                        return;
                     end if;
                     Budget := Budget - 1;
                     Init (State, Init_OK, State.OSR + 1);
                     if not Init_OK then
                        Latch_Off;
                        return;
                     end if;
                     Recovered := True;
                     if State.Resets < Natural'Last then
                        State.Resets := State.Resets + 1;
                     end if;
                     State.Last_Health := Intermittent;
                     Restart := True;

                  when Permanent =>
                     Latch_Off;
                     return;
               end case;
            end loop;

            pragma Assert (if Restart then Budget < Budget_Start else Budget = Budget_Start);
            if not Restart then
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
            end if;
         end loop;

         exit when not Restart;
      end loop;

      OK := True;
   end Generate;

end SPARKEntropy;
