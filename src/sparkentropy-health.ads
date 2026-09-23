--  NIST SP 800-90B health tests for jitter entropy, with the two failure
--  tiers of jitterentropy (SP 800-90B 4.3): intermittent cutoffs at
--  alpha = 2^-30 and permanent ones at 2^-60 for the RCT and APT; the
--  vendor lag predictor test uses 2^-22 and 2^-44 (its window is much
--  larger). Cutoff tables are jitterentropy's, indexed by the
--  oversampling rate, because they encode the same 1/OSR entropy claim.
--
--  Repetition Count Test (RCT): detects consecutive stuck samples
--  Adaptive Proportion Test (APT): detects repeating patterns
--  Lag Predictor Test: detects predictable time delta sequences
--
--  SHAKE.SHAKE256.States is already use-type'd at the parent level
--  (SPARKEntropy.ads); no separate import needed here.
package SPARKEntropy.Health with
   SPARK_Mode => On
is

   --  Update RCT with a new stuck/not-stuck observation.
   procedure Update_RCT
     (State  : in out Entropy_State;
      Stuck  : Boolean;
      Status : out Health_Status)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool)'Old;

   --  Update APT with a new time delta.
   procedure Update_APT
     (State  : in out Entropy_State;
      Dt     : U64;
      Status : out Health_Status)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool)'Old;

   --  Update lag predictor with a new time delta.
   procedure Update_Lag
     (State  : in out Entropy_State;
      Dt     : U64;
      Status : out Health_Status)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool)'Old;

   --  Run all health tests for one sample. Permanent if any test failed
   --  permanently, else Intermittent if any failed intermittently.
   procedure Check_Health
     (State  : in out Entropy_State;
      Dt     : U64;
      Stuck  : Boolean;
      Status : out Health_Status)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool)'Old;

   --  Reset all health test state (called during init and after an
   --  intermittent failure).
   procedure Reset_Health (State : in out Entropy_State)
   with Post => SHAKE.SHAKE256.State_Of (State.Pool) =
                  SHAKE.SHAKE256.State_Of (State.Pool)'Old;

end SPARKEntropy.Health;
