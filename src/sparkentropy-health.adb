--  Health test implementation.
--
--  Cutoff values are from the Jitterentropy reference implementation,
--  computed for alpha = 2^-30 (intermittent) and 2^-60 (permanent).

package body SPARKEntropy.Health with
   SPARK_Mode => On
is
   --================================================================
   --  RCT: Repetition Count Test (SP 800-90B §4.4.1)
   --  Counts consecutive stuck measurements.
   --================================================================

   RCT_Cutoff_Factor : constant := 30;

   procedure Update_RCT
     (State  : in out Entropy_State;
      Stuck  : Boolean;
      Failed : out Boolean)
   is
   begin
      if Stuck then
         if State.RCT.Count < RCT_Counter'Last then
            State.RCT.Count := State.RCT.Count + 1;
         end if;
      else
         State.RCT.Count := 0;
      end if;
      Failed := State.RCT.Count >=
         RCT_Cutoff_Factor * Natural (State.OSR);
   end Update_RCT;

   --================================================================
   --  APT: Adaptive Proportion Test (SP 800-90B §4.4.2)
   --================================================================

   type APT_Cutoff_Table is array (OSR_Range) of Natural;
   APT_Cutoffs : constant APT_Cutoff_Table :=
     (3 => 459, 4 => 434, 5 => 419,
      6 => 408, 7 => 400, 8 => 394,
      9 => 389, 10 => 385, 11 => 381,
      12 => 378, 13 => 376, 14 => 374,
      15 => 372, 16 => 370, 17 => 369,
      18 => 367, 19 => 366, 20 => 365);

   procedure Update_APT
     (State  : in out Entropy_State;
      Dt     : U64;
      Failed : out Boolean)
   is
   begin
      Failed := False;

      if not State.APT.Active then
         State.APT.Base_Value := Dt;
         State.APT.Count := 0;
         State.APT.Window_Pos := 0;
         State.APT.Active := True;
         return;
      end if;

      if State.APT.Window_Pos < APT_Counter'Last then
         State.APT.Window_Pos := State.APT.Window_Pos + 1;
      end if;

      if Dt = State.APT.Base_Value
         and then State.APT.Count < APT_Counter'Last
      then
         State.APT.Count := State.APT.Count + 1;
      end if;

      if State.APT.Window_Pos = APT_Window_Size then
         Failed := State.APT.Count >= APT_Cutoffs (State.OSR);
         State.APT.Active := False;
      end if;
   end Update_APT;

   --================================================================
   --  Lag Predictor Test (vendor-defined)
   --================================================================

   Lag_Global_Cutoff : constant := 114860;

   procedure Update_Lag
     (State  : in out Entropy_State;
      Dt     : U64;
      Failed : out Boolean)
   is
      Initial_Pool_State : constant SHAKE.SHAKE256.States :=
         SHAKE.SHAKE256.State_Of (State.Pool)
      with Ghost;
      Best_Diff : U64 := U64'Last;
      Diff      : U64;
   begin
      Failed := False;

      for I in Lag_Index loop
         if Dt > State.Lag.History (I) then
            Diff := Dt - State.Lag.History (I);
         else
            Diff := State.Lag.History (I) - Dt;
         end if;
         if Diff < Best_Diff then
            Best_Diff := Diff;
         end if;
      end loop;

      if Best_Diff = 0 then
         if State.Lag.Predict_Count < Lag_Counter'Last then
            State.Lag.Predict_Count := State.Lag.Predict_Count + 1;
         end if;
         if State.Lag.Consec_Count < Lag_Counter'Last then
            State.Lag.Consec_Count := State.Lag.Consec_Count + 1;
         end if;
      else
         State.Lag.Consec_Count := 0;
      end if;

      State.Lag.History (State.Lag.Pos) := Dt;
      if State.Lag.Pos < Lag_Index'Last then
         State.Lag.Pos := State.Lag.Pos + 1;
      else
         State.Lag.Pos := 0;
      end if;

      if State.Lag.Window_Pos < Lag_Counter'Last then
         State.Lag.Window_Pos := State.Lag.Window_Pos + 1;
      end if;

      if State.Lag.Window_Pos = Lag_Window_Size then
         Failed := State.Lag.Predict_Count >= Lag_Global_Cutoff;
         State.Lag.Predict_Count := 0;
         State.Lag.Consec_Count := 0;
         State.Lag.Window_Pos := 0;
      end if;

      pragma Assert
        (SHAKE.SHAKE256.State_Of (State.Pool) = Initial_Pool_State);
   end Update_Lag;

   --================================================================
   --  Combined health check
   --================================================================

   procedure Check_Health
     (State  : in out Entropy_State;
      Dt     : U64;
      Stuck  : Boolean;
      Failed : out Boolean)
   is
      RCT_Fail, APT_Fail, Lag_Fail : Boolean;
   begin
      Update_RCT (State, Stuck, RCT_Fail);
      Update_APT (State, Dt, APT_Fail);
      Update_Lag (State, Dt, Lag_Fail);
      Failed := RCT_Fail or APT_Fail or Lag_Fail;
   end Check_Health;

   --================================================================
   --  Reset
   --================================================================

   procedure Reset_Health (State : in out Entropy_State) is
   begin
      State.RCT := (Count => 0);
      State.APT := (Base_Value => 0, Count => 0,
                     Window_Pos => 0, Active => False);
      State.Lag := (History => (others => 0), Pos => 0,
                    Best_Lag => 0, Predict_Count => 0,
                    Consec_Count => 0, Window_Pos => 0);
      State.Stuck_Count := 0;
   end Reset_Health;

end SPARKEntropy.Health;
