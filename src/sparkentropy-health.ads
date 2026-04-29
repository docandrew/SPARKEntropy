--  NIST SP 800-90B health tests for jitter entropy.
--
--  Repetition Count Test (RCT): detects consecutive stuck samples
--  Adaptive Proportion Test (APT): detects repeating patterns
--  Lag Predictor Test: detects predictable time delta sequences

--  SHAKE.SHAKE256.States is already use-type'd at the parent level
--  (SPARKEntropy.ads); no separate import needed here.

package SPARKEntropy.Health with
   SPARK_Mode => On
is
   --  Update RCT with a new stuck/not-stuck observation.
   --  Returns True if the test fails (too many consecutive stuck).
   procedure Update_RCT
     (State  : in out Entropy_State;
      Stuck  : Boolean;
      Failed : out Boolean)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool)'Old;

   --  Update APT with a new time delta.
   --  Returns True if the test fails (too many repetitions).
   procedure Update_APT
     (State  : in out Entropy_State;
      Dt     : U64;
      Failed : out Boolean)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool)'Old;

   --  Update lag predictor with a new time delta.
   --  Returns True if the test fails (too predictable).
   procedure Update_Lag
     (State  : in out Entropy_State;
      Dt     : U64;
      Failed : out Boolean)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool)'Old;

   --  Run all health tests for one sample.
   --  Returns True if any test fails.
   procedure Check_Health
     (State  : in out Entropy_State;
      Dt     : U64;
      Stuck  : Boolean;
      Failed : out Boolean)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool)'Old;

   --  Reset all health test state (called during init).
   procedure Reset_Health (State : in out Entropy_State)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool)'Old;

end SPARKEntropy.Health;
