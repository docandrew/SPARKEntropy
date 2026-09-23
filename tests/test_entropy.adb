--  Smoke test: the generator initialises and produces output on this
--  machine, and the health tests classify failures into the two SP
--  800-90B tiers at jitterentropy's cutoffs (fed directly, since a live
--  source does not trip them on demand).
with Ada.Text_IO;    use Ada.Text_IO;
with Ada.Command_Line;
with Interfaces;     use Interfaces;
with SPARKEntropy;   use SPARKEntropy;
with SPARKEntropy.Health;

procedure Test_Entropy is
   State : Entropy_State;
   OK    : Boolean;
   Buf   : Byte_Seq (0 .. 31);
   Fail  : Natural := 0;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      if Cond then
         Put_Line ("  PASS: " & Name);
      else
         Put_Line ("  FAIL: " & Name);
         Fail := Fail + 1;
      end if;
   end Check;

   --  Drive one test with N identical observations; report the status
   --  after the last one.
   function RCT_After (S : in out Entropy_State; N : Positive) return Health_Status is
      St : Health_Status := Healthy;
   begin
      for I in 1 .. N loop
         Health.Update_RCT (S, True, St);
      end loop;
      return St;
   end RCT_After;

   function APT_After (S : in out Entropy_State; N : Positive) return Health_Status is
      St : Health_Status := Healthy;
   begin
      for I in 1 .. N loop
         Health.Update_APT (S, 12345, St);
      end loop;
      return St;
   end APT_After;

   function Lag_After (S : in out Entropy_State; N : Positive) return Health_Status is
      St : Health_Status := Healthy;
   begin
      for I in 1 .. N loop
         Health.Update_Lag (S, 777, St);
      end loop;
      return St;
   end Lag_After;

   procedure Health_Tiers is
      S  : Entropy_State;   --  default OSR = Min_OSR = 3
      St : Health_Status;
   begin
      Put_Line ("Health tiers at OSR 3 (jitterentropy cutoffs)");
      --  RCT: 30 * OSR = 90 intermittent, 60 * OSR = 180 permanent
      Health.Reset_Health (S);
      Check ("RCT: 89 stuck -> Healthy", RCT_After (S, 89) = Healthy);
      Health.Update_RCT (S, True, St);
      Check ("RCT: 90th stuck -> Intermittent", St = Intermittent);
      Check ("RCT: 179th stuck -> still Intermittent", RCT_After (S, 89) = Intermittent);
      Health.Update_RCT (S, True, St);
      Check ("RCT: 180th stuck -> Permanent", St = Permanent);
      Health.Update_RCT (S, False, St);
      Check ("RCT: a non-stuck delta clears the count", St = Healthy);

      --  APT: base counts as one; cutoffs 459 intermittent, 479 permanent
      Health.Reset_Health (S);
      Check ("APT: 458 repeats of the base -> Healthy", APT_After (S, 458) = Healthy);
      Health.Update_APT (S, 12345, St);
      Check ("APT: 459th -> Intermittent", St = Intermittent);
      Check ("APT: 478th -> still Intermittent", APT_After (S, 19) = Intermittent);
      Health.Update_APT (S, 12345, St);
      Check ("APT: 479th -> Permanent", St = Permanent);
      Health.Reset_Health (S);
      Health.Update_APT (S, 1, St);
      Health.Update_APT (S, 2, St);
      Check ("APT: a different delta is not counted", St = Healthy);

      --  Lag predictor: local cutoffs 111 intermittent, 177 permanent on
      --  a constant delta (every predictor is right every time)
      Health.Reset_Health (S);
      Check ("Lag: 8 fill + 110 hits -> Healthy", Lag_After (S, 8 + 110) = Healthy);
      Health.Update_Lag (S, 777, St);
      Check ("Lag: 111th hit -> Intermittent", St = Intermittent);
      Check ("Lag: 176th hit -> still Intermittent", Lag_After (S, 65) = Intermittent);
      Health.Update_Lag (S, 777, St);
      Check ("Lag: 177th hit -> Permanent", St = Permanent);
      Health.Reset_Health (S);
      for I in 1 .. 200 loop
         Health.Update_Lag (S, U64 (I) * 7919, St);
      end loop;
      Check ("Lag: distinct deltas never predicted", St = Healthy);

      --  Combined verdict is the worst of the three
      Health.Reset_Health (S);
      for I in 1 .. 179 loop
         Health.Check_Health (S, U64 (I), True, St);
      end loop;
      Check ("Check_Health: RCT intermittent dominates a healthy APT/lag", St = Intermittent);
      Health.Check_Health (S, 180, True, St);
      Check ("Check_Health: permanent dominates", St = Permanent);
   end Health_Tiers;

begin
   Put_Line ("SPARKEntropy Test");
   Put_Line ("=================");

   Health_Tiers;

   Put ("Initializing (1024 samples)... ");
   Init (State, OK);
   if not OK then
      Put_Line ("FAILED - timer unsuitable or start-up health failure");
      Ada.Command_Line.Set_Exit_Status (1);
      return;
   end if;
   Put_Line ("OK (OSR" & Current_OSR (State)'Image & ", health "
             & Last_Health (State)'Image & ")");

   for Round in 1 .. 5 loop
      Put ("Generate 32 bytes #" & Round'Image & ": ");
      Generate (State, Buf, OK);
      if not OK then
         Put_Line ("FAILED - permanent health failure");
         Ada.Command_Line.Set_Exit_Status (1);
         return;
      end if;
      for I in Buf'Range loop
         declare
            V : constant Unsigned_8 := Unsigned_8 (Buf (I));
            Hi : constant Natural := Natural (Shift_Right (V, 4));
            Lo : constant Natural := Natural (V and 16#0F#);
            Hex : constant String := "0123456789abcdef";
         begin
            Put (Hex (Hi + 1) & Hex (Lo + 1));
         end;
      end loop;
      New_Line;
   end loop;
   Check ("Generate: no intermittent reset in 5 blocks", Intermittent_Resets (State) = 0);
   Check ("Generate: health Healthy", Last_Health (State) = Healthy);

   if Fail > 0 then
      Put_Line ("FAIL:" & Fail'Image & " checks");
      Ada.Command_Line.Set_Exit_Status (1);
   else
      Put_Line ("PASS");
   end if;
end Test_Entropy;
