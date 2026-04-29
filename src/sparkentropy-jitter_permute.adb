--  Keccak-f[1600] permutation (entropy-jitter use only).
--
--  Reference: FIPS 202 (SHA-3 Standard).
--  This is NOT the cryptographic SHAKE-256 -- that lives in libkeccak
--  via SHAKE.SHAKE256. We keep just the raw permutation here as a
--  variable-execution-time CPU stressor for noise.adb's Hash_Loop.
--
--  The permutation follows the specification exactly:
--    theta -> rho -> pi -> chi -> iota (24 rounds)

package body SPARKEntropy.Jitter_Permute with
   SPARK_Mode => On
is

   --================================================================
   --  Keccak-f[1600] round constants
   --================================================================

   RC : constant array (0 .. 23) of U64 :=
     (16#0000000000000001#, 16#0000000000008082#,
      16#800000000000808A#, 16#8000000080008000#,
      16#000000000000808B#, 16#0000000080000001#,
      16#8000000080008081#, 16#8000000000008009#,
      16#000000000000008A#, 16#0000000000000088#,
      16#0000000080008009#, 16#000000008000000A#,
      16#000000008000808B#, 16#800000000000008B#,
      16#8000000000008089#, 16#8000000000008003#,
      16#8000000000008002#, 16#8000000000000080#,
      16#000000000000800A#, 16#800000008000000A#,
      16#8000000080008081#, 16#8000000000008080#,
      16#0000000080000001#, 16#8000000080008008#);


   --================================================================
   --  Keccak-f[1600] permutation
   --================================================================

   procedure Permute (S : in out Keccak_State) is
      subtype Coord is Natural range 0 .. 4;
      C : array (Coord) of U64;
      D : U64;
      B : Keccak_State;
   begin
      for Round in 0 .. 23 loop
         --  Theta
         for X in Coord loop
            C (X) := S (X) xor S (X + 5) xor S (X + 10)
                     xor S (X + 15) xor S (X + 20);
         end loop;
         for X in Coord loop
            D := C ((X + 4) mod 5)
                 xor Rotate_Left (C ((X + 1) mod 5), 1);
            for Y in Coord loop
               S (X + 5 * Y) := S (X + 5 * Y) xor D;
            end loop;
         end loop;

         --  Rho + Pi (FIPS 202 §3.2.2)
         B := (others => 0);
         B (0) := S (0);

         declare
            X   : Coord := 1;
            Y   : Coord := 0;
            Cur : U64;
            Rot : Natural;
         begin
            for T in 0 .. 23 loop
               Rot := ((T + 1) * (T + 2) / 2) mod 64;
               Cur := Rotate_Left (S (X + 5 * Y), Rot);
               declare
                  NX : constant Coord := Y;
                  NY : constant Coord := (2 * X + 3 * Y) mod 5;
               begin
                  B (NX + 5 * NY) := Cur;
                  X := NX;
                  Y := NY;
               end;
            end loop;
         end;

         --  Chi
         for Y in Coord loop
            for X in Coord loop
               S (X + 5 * Y) :=
                  B (X + 5 * Y)
                  xor ((not B (((X + 1) mod 5) + 5 * Y))
                       and B (((X + 2) mod 5) + 5 * Y));
            end loop;
         end loop;

         --  Iota
         S (0) := S (0) xor RC (Round);
      end loop;
   end Permute;

end SPARKEntropy.Jitter_Permute;
