--  SPARKEntropy — SPARK/Ada Jitterentropy Implementation
--
--  CSPRNG using CPU timing jitter. Based on the Jitterentropy algorithm by
--  Stephan Mueller.
--
--  No heap allocation.  All state is in the Entropy_State record.
--  The only platform dependency is the high-resolution timer
--  (rdtsc on x86/x86_64, CNTVCT_EL0 on AArch64).
--
--  Usage:
--    State : SPARKEntropy.Entropy_State;
--    OK    : Boolean;
--    Buf   : SPARKEntropy.Byte_Seq (0 .. 31);
--
--    SPARKEntropy.Init (State, OK);
--    if OK then
--       SPARKEntropy.Generate (State, Buf, OK);
--    end if;

with Interfaces; use Interfaces;
with SHAKE;
use type SHAKE.SHAKE256.States;

package SPARKEntropy with
   SPARK_Mode => On
is
   ----------------------------------------------------------------------------
   --  Basic types
   ----------------------------------------------------------------------------

   type Byte is new Unsigned_8;
   type Byte_Seq is array (Natural range <>) of Byte;

   subtype U64 is Unsigned_64;

   ----------------------------------------------------------------------------
   --  Constants (matching Jitterentropy defaults)
   ----------------------------------------------------------------------------

   --  Oversampling rate (OSR): the number of non-stuck time deltas
   --  absorbed per output bit. The generator credits each delta with
   --  1/OSR bit of min-entropy, whatever the platform actually delivers,
   --  and fills a 256-bit block from (256 + Entropy_Safety_Factor) * OSR
   --  deltas, so a noise source that meets 1/OSR per delta gives
   --  full-entropy output. Init takes the value; the bounds are
   --  jitterentropy's (JENT_MIN_OSR 3, and 20 as the largest rate at
   --  which it will still run). Raising OSR costs output speed only.
   Min_OSR : constant := 3;
   Max_OSR : constant := 20;

   --  Memory noise source buffer: 2^18 = 256 KB
   Memory_Bits    : constant := 18;
   Memory_Size    : constant := 2 ** Memory_Bits;
   Memory_Mask    : constant := Memory_Size - 1;
   Mem_Block_Size : constant := 128;
   Mem_Loops      : constant := 128;

   --  Hash noise source
   Hash_Loops : constant := 1;

   --  Health test windows
   APT_Window_Size : constant := 512;
   Lag_Window_Size : constant := 131072;
   Lag_History     : constant := 8;

   --  Power-up self-test
   Powerup_Loops : constant := 1024;

   --  Entropy safety factor (FIPS mode, SP 800-90C appendix A.4)
   Entropy_Safety_Factor : constant := 65;

   --  Output block size (256 bits = 32 bytes)
   Block_Size : constant := 32;

   ----------------------------------------------------------------------------
   --  Entropy collector state
   ----------------------------------------------------------------------------

   ----------------------------------------------------------------------------
   --  Internal types
   ----------------------------------------------------------------------------

   --  Raw Keccak-f[1600] state (1600 bits = 25 × 64-bit lanes).
   --  Used ONLY for noise.adb's timing-jitter loop, never for crypto.
   type Keccak_State is array (0 .. 24) of U64;

   --  xoshiro128** PRNG for memory access randomization
   type Xoshiro_State is record
      S0, S1, S2, S3 : Unsigned_32 := 0;
   end record;

   --  Health test state (bounded subtypes prevent overflow)
   Max_RCT_Count : constant := 30 * Max_OSR;  --  600

   subtype RCT_Counter    is Natural range 0 .. Max_RCT_Count;
   subtype APT_Counter    is Natural range 0 .. APT_Window_Size;
   subtype Lag_Counter    is Natural range 0 .. Lag_Window_Size;
   subtype Lag_Index      is Natural range 0 .. Lag_History - 1;

   type APT_State is record
      Base_Value  : U64 := 0;
      Count       : APT_Counter := 0;
      Window_Pos  : APT_Counter := 0;
      Active      : Boolean := False;
   end record;

   type RCT_State is record
      Count : RCT_Counter := 0;
   end record;

   type Lag_History_Arr is array (Lag_Index) of U64;

   type Lag_State is record
      History       : Lag_History_Arr := (others => 0);
      Pos           : Lag_Index := 0;
      Best_Lag      : Lag_Index := 0;
      Predict_Count : Lag_Counter := 0;
      Consec_Count  : Lag_Counter := 0;
      Window_Pos    : Lag_Counter := 0;
   end record;

   --  Memory noise source buffer
   subtype Mem_Index is Natural range 0 .. Memory_Size - 1;
   type Mem_Buffer is array (Mem_Index) of Byte;

   subtype OSR_Range is Natural range Min_OSR .. Max_OSR;

   type Entropy_State is record
      --  Conditioning sponge (SHAKE-256 from libkeccak)
      --  Time deltas are absorbed via Update; Generate extracts blocks.
      Pool : SHAKE.SHAKE256.Context;

      --  Raw Keccak state used only by noise.adb's Hash_Loop as a
      --  variable-execution-time CPU stressor for entropy gathering.
      Jitter_State : Keccak_State := (others => 0);

      --  Previous timestamp and derivatives (for stuck test)
      Prev_Time  : U64 := 0;
      Prev_Delta : U64 := 0;
      Prev_Delta2 : U64 := 0;

      --  GCD of all time deltas (computed during init)
      Timer_GCD : U64 := 0;

      --  Oversampling rate, set by Init (see Min_OSR)
      OSR : OSR_Range := Min_OSR;

      --  Health tests
      APT : APT_State;
      RCT : RCT_State;
      Lag : Lag_State;
      Stuck_Count : Natural := 0;

      --  Memory noise source
      Mem : Mem_Buffer := (others => 0);
      Mem_Location : Mem_Index := 0;
      Xo  : Xoshiro_State;

      --  Initialization flag
      Initialized : Boolean := False;
   end record;

   ----------------------------------------------------------------------------
   --  Public API
   ----------------------------------------------------------------------------

   --  Initialize the entropy collector.
   --  Runs power-up self-test (1024 samples), validates timer,
   --  computes GCD, checks health tests.
   --  Returns OK = False if the platform timer is unsuitable.
   --
   --  OSR is the oversampling rate for this platform (see Min_OSR): the
   --  claim that each time delta carries at least 1/OSR bit of
   --  min-entropy. The right value comes from the SP 800-90B assessment
   --  of the raw deltas (ci/nist_entropy.sh, tests/dump_raw.adb): the
   --  measured min-entropy per delta must be at least 1/OSR, so
   --  OSR = ceiling (1 / H_min), never below Min_OSR. A platform whose
   --  timer is coarse or whose execution is too regular for the default
   --  needs a larger OSR, not a lower pass mark; the cost is output
   --  speed. The health-test cutoffs (RCT, APT, lag predictor) are
   --  calibrated to the same 1/OSR assumption and scale with it.
   --
   --  State is `in out` (not `out`) so the caller's default-
   --  initialized declaration carries the type's declared field
   --  defaults through to Init's body. SPARK forbids
   --  `(others => <>)` aggregates in `out`-only contexts; relying
   --  on the existing field defaults is the equivalent.
   procedure Init
     (State : in out Entropy_State;
      OK    : out Boolean;
      OSR   : OSR_Range := Min_OSR)
   with Post => (if OK then
                    SHAKE.SHAKE256.State_Of (State.Pool) =
                      SHAKE.SHAKE256.Updating);

   --  Generate random bytes.
   --  Output'Length can be any size; internally generates 32-byte
   --  blocks and truncates the last one.
   --  Returns OK = False on health test failure; Output is then all
   --  zero and the generator is latched off (Initialized cleared) until
   --  Init is called again.
   procedure Generate
     (State  : in out Entropy_State;
      Output : out Byte_Seq;
      OK     : out Boolean)
   with Pre => Output'Length > 0
               and Output'Last < Natural'Last
               and SHAKE.SHAKE256.State_Of (State.Pool) =
                     SHAKE.SHAKE256.Updating;

end SPARKEntropy;
