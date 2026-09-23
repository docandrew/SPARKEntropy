--  Health test implementation.
--
--  Cutoff values and test mechanics follow jitterentropy
--  (src/jitterentropy-health.c): intermittent cutoffs computed for
--  alpha = 2^-30, permanent ones for 2^-60 (lag predictor: 2^-22 and
--  2^-44), each assuming 1/OSR bit of entropy per delta.
package body SPARKEntropy.Health with
   SPARK_Mode => On
is

   ----------------------------------------------------------------------------
   --  RCT: Repetition Count Test (SP 800-90B 4.4.1)
   --  Counts consecutive stuck measurements. Cutoff C = 1 + ceil(-log2
   --  (alpha) / H) with H = 1/OSR: 30 * OSR intermittent, 60 * OSR
   --  permanent (jitterentropy JENT_HEALTH_RCT_*_CUTOFF).
   ----------------------------------------------------------------------------

   RCT_Intermittent_Factor : constant := 30;
   RCT_Permanent_Factor    : constant := 60;

   procedure Update_RCT
     (State  : in out Entropy_State;
      Stuck  : Boolean;
      Status : out Health_Status)
   is
   begin
      Status := Healthy;
      if Stuck then
         if State.RCT.Count < RCT_Counter'Last then
            State.RCT.Count := State.RCT.Count + 1;
         end if;
         if State.RCT.Count >= RCT_Permanent_Factor * Natural (State.OSR) then
            Status := Permanent;
         elsif State.RCT.Count >= RCT_Intermittent_Factor * Natural (State.OSR) then
            Status := Intermittent;
         end if;
      else
         State.RCT.Count := 0;
      end if;
   end Update_RCT;

   ----------------------------------------------------------------------------
   --  APT: Adaptive Proportion Test (SP 800-90B 4.4.2)
   --  Window of APT_Window_Size deltas; the first is the base and counts
   --  as one occurrence; the test fails when the base recurs too often.
   ----------------------------------------------------------------------------

   type APT_Cutoff_Table is array (OSR_Range) of Natural;

   --  jitterentropy jent_apt_cutoff_lookup, entries for OSR 3 .. 20
   APT_Cutoffs : constant APT_Cutoff_Table :=
     (3 => 459, 4 => 477, 5 => 488, 6 => 494, 7 => 499, 8 => 502,
      9 => 505, 10 => 507, 11 => 508, 12 => 509, 13 => 510, 14 => 511,
      15 => 512, 16 => 512, 17 => 512, 18 => 512, 19 => 512, 20 => 512);

   --  jitterentropy jent_apt_cutoff_permanent_lookup, entries for OSR 3 .. 20
   APT_Cutoffs_Permanent : constant APT_Cutoff_Table :=
     (3 => 479, 4 => 494, 5 => 502, 6 => 507, 7 => 510, 8 => 512,
      9 => 512, 10 => 512, 11 => 512, 12 => 512, 13 => 512, 14 => 512,
      15 => 512, 16 => 512, 17 => 512, 18 => 512, 19 => 512, 20 => 512);

   procedure Update_APT
     (State  : in out Entropy_State;
      Dt     : U64;
      Status : out Health_Status)
   is
   begin
      Status := Healthy;

      if not State.APT.Active then
         --  APT step 1: the first delta of a window is the base, one
         --  occurrence and one observation.
         State.APT.Base_Value := Dt;
         State.APT.Count := 1;
         State.APT.Window_Pos := 1;
         State.APT.Active := True;
         return;
      end if;

      if Dt = State.APT.Base_Value then
         if State.APT.Count < APT_Counter'Last then
            State.APT.Count := State.APT.Count + 1;
         end if;
         if State.APT.Count >= APT_Cutoffs_Permanent (State.OSR) then
            Status := Permanent;
         elsif State.APT.Count >= APT_Cutoffs (State.OSR) then
            Status := Intermittent;
         end if;
      end if;

      if State.APT.Window_Pos < APT_Counter'Last then
         State.APT.Window_Pos := State.APT.Window_Pos + 1;
      end if;

      --  APT step 4: window complete, the next delta starts a new one.
      if State.APT.Window_Pos = APT_Window_Size then
         State.APT.Active := False;
      end if;
   end Update_APT;

   ----------------------------------------------------------------------------
   --  Lag Predictor Test (vendor-defined, jitterentropy)
   --  Lag_History sub-predictors; the best-scoring one's guess is tested
   --  against each delta. Global cutoff: correct predictions per window
   --  (InverseBinomialCDF at p = 2^(-1/OSR)); local cutoff: longest run
   --  of correct predictions. Window Lag_Window_Size deltas.
   ----------------------------------------------------------------------------

   type Lag_Cutoff_Table is array (OSR_Range) of Natural;

   --  jitterentropy jent_lag_global_cutoff_lookup, OSR 3 .. 20
   Lag_Global : constant Lag_Cutoff_Table :=
     (3 => 104761, 4 => 110875, 5 => 114707, 6 => 117330, 7 => 119237,
      8 => 120686, 9 => 121823, 10 => 122739, 11 => 123493, 12 => 124124,
      13 => 124660, 14 => 125120, 15 => 125520, 16 => 125871, 17 => 126181,
      18 => 126457, 19 => 126704, 20 => 126926);

   --  jitterentropy jent_lag_global_cutoff_permanent_lookup, OSR 3 .. 20
   Lag_Global_Permanent : constant Lag_Cutoff_Table :=
     (3 => 105108, 4 => 111188, 5 => 114993, 6 => 117596, 7 => 119486,
      8 => 120920, 9 => 122045, 10 => 122951, 11 => 123696, 12 => 124318,
      13 => 124847, 14 => 125301, 15 => 125695, 16 => 126041, 17 => 126346,
      18 => 126617, 19 => 126860, 20 => 127079);

   --  jitterentropy jent_lag_local_cutoff_lookup, OSR 3 .. 20
   Lag_Local : constant Lag_Cutoff_Table :=
     (3 => 111, 4 => 146, 5 => 181, 6 => 215, 7 => 250, 8 => 284,
      9 => 318, 10 => 351, 11 => 385, 12 => 419, 13 => 452, 14 => 485,
      15 => 518, 16 => 551, 17 => 584, 18 => 617, 19 => 650, 20 => 683);

   --  jitterentropy jent_lag_local_cutoff_permanent_lookup, OSR 3 .. 20
   Lag_Local_Permanent : constant Lag_Cutoff_Table :=
     (3 => 177, 4 => 234, 5 => 291, 6 => 347, 7 => 404, 8 => 460,
      9 => 516, 10 => 571, 11 => 627, 12 => 683, 13 => 738, 14 => 793,
      15 => 848, 16 => 903, 17 => 958, 18 => 1013, 19 => 1068, 20 => 1123);

   procedure Update_Lag
     (State  : in out Entropy_State;
      Dt     : U64;
      Status : out Health_Status)
   is
      Initial_Pool_State : constant SHAKE.SHAKE256.States :=
         SHAKE.SHAKE256.State_Of (State.Pool)
      with Ghost;
      Slot : Lag_Index;
   begin
      Status := Healthy;

      --  The first Lag_History deltas only fill the history.
      if State.Lag.Observations < Lag_History then
         State.Lag.History (State.Lag.Observations) := Dt;
         State.Lag.Observations := State.Lag.Observations + 1;
         pragma Assert
           (SHAKE.SHAKE256.State_Of (State.Pool) = Initial_Pool_State);
         return;
      end if;

      --  Test the best predictor's guess.
      if State.Lag.History (State.Lag.Best) = Dt then
         if State.Lag.Success_Count < Lag_Counter'Last then
            State.Lag.Success_Count := State.Lag.Success_Count + 1;
         end if;
         if State.Lag.Success_Run < Lag_Counter'Last then
            State.Lag.Success_Run := State.Lag.Success_Run + 1;
         end if;
         if State.Lag.Success_Run >= Lag_Local_Permanent (State.OSR)
           or else State.Lag.Success_Count >= Lag_Global_Permanent (State.OSR)
         then
            Status := Permanent;
         elsif State.Lag.Success_Run >= Lag_Local (State.OSR)
           or else State.Lag.Success_Count >= Lag_Global (State.OSR)
         then
            Status := Intermittent;
         end if;
      else
         State.Lag.Success_Run := 0;
      end if;

      --  Score every predictor that would have been right; the best one
      --  makes the next prediction.
      for I in Lag_Index loop
         pragma Loop_Invariant
           (SHAKE.SHAKE256.State_Of (State.Pool) = Initial_Pool_State);
         if State.Lag.History (I) = Dt then
            if State.Lag.Scoreboard (I) < Lag_Counter'Last then
               State.Lag.Scoreboard (I) := State.Lag.Scoreboard (I) + 1;
            end if;
            if State.Lag.Scoreboard (I) > State.Lag.Scoreboard (State.Lag.Best) then
               State.Lag.Best := I;
            end if;
         end if;
      end loop;

      --  Record the delta in the ring and count the observation.
      Slot := State.Lag.Observations mod Lag_History;
      State.Lag.History (Slot) := Dt;
      if State.Lag.Observations < Lag_Counter'Last then
         State.Lag.Observations := State.Lag.Observations + 1;
      end if;

      --  Window complete: start over (history and scores included).
      if State.Lag.Observations = Lag_Window_Size then
         State.Lag := (History => (others => 0), Scoreboard => (others => 0),
                       Best => 0, Observations => 0,
                       Success_Count => 0, Success_Run => 0);
      end if;

      pragma Assert
        (SHAKE.SHAKE256.State_Of (State.Pool) = Initial_Pool_State);
   end Update_Lag;

   ----------------------------------------------------------------------------
   --  Combined health check
   ----------------------------------------------------------------------------

   procedure Check_Health
     (State  : in out Entropy_State;
      Dt     : U64;
      Stuck  : Boolean;
      Status : out Health_Status)
   is
      RCT_S, APT_S, Lag_S : Health_Status;
   begin
      Update_RCT (State, Stuck, RCT_S);
      Update_APT (State, Dt, APT_S);
      Update_Lag (State, Dt, Lag_S);
      Status := Health_Status'Max (RCT_S, Health_Status'Max (APT_S, Lag_S));
   end Check_Health;

   ----------------------------------------------------------------------------
   --  Reset
   ----------------------------------------------------------------------------

   procedure Reset_Health (State : in out Entropy_State) is
   begin
      State.RCT := (Count => 0);
      State.APT := (Base_Value => 0, Count => 0,
                    Window_Pos => 0, Active => False);
      State.Lag := (History => (others => 0), Scoreboard => (others => 0),
                    Best => 0, Observations => 0,
                    Success_Count => 0, Success_Run => 0);
      State.Stuck_Count := 0;
   end Reset_Health;

end SPARKEntropy.Health;
