--  Keccak-f[1600] and SHAKE-256 implementation
--
--  Reference: FIPS 202 (SHA-3 Standard)
--  The permutation follows the specification exactly:
--    theta -> rho -> pi -> chi -> iota (24 rounds)

package body SPARKEntropy.Keccak with
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

   --================================================================
   --  SHAKE-256 sponge operations
   --================================================================

   procedure Reset (Sp : out Sponge) is
   begin
      Sp := (S        => (others => 0),
             Partial  => (others => 0),
             Absorbed => 0,
             Squeezed => False);
   end Reset;

   --  XOR a byte into the state at byte position Pos
   procedure XOR_Byte (S : in out Keccak_State;
                       Pos : Natural;
                       Val : Byte)
   with Pre => Pos < 200
   is
      Lane : constant Natural := Pos / 8;
      Off  : constant Natural := (Pos mod 8) * 8;
   begin
      S (Lane) := S (Lane) xor Shift_Left (U64 (Val), Off);
   end XOR_Byte;

   --  Extract a byte from the state at byte position Pos
   function Get_Byte (S : Keccak_State;
                      Pos : Natural) return Byte
   with Pre => Pos < 200
   is
      Lane : constant Natural := Pos / 8;
      Off  : constant Natural := (Pos mod 8) * 8;
   begin
      return Byte (Shift_Right (S (Lane), Off) and 16#FF#);
   end Get_Byte;

   procedure Absorb
     (Sp   : in out Sponge;
      Data : Byte_Seq)
   is
   begin
      for I in Data'Range loop
         XOR_Byte (Sp.S, Sp.Absorbed, Data (I));
         if Sp.Absorbed < Shake256_Rate - 1 then
            Sp.Absorbed := Sp.Absorbed + 1;
         else
            --  Block full, permute and reset
            Permute (Sp.S);
            Sp.Absorbed := 0;
         end if;
      end loop;
   end Absorb;

   procedure Absorb_U64
     (Sp  : in out Sponge;
      Val : U64)
   is
      Buf : Byte_Seq (0 .. 7) := (others => 0);
   begin
      --  Little-endian encoding
      Buf (0) := Byte (Val and 16#FF#);
      Buf (1) := Byte (Shift_Right (Val, 8) and 16#FF#);
      Buf (2) := Byte (Shift_Right (Val, 16) and 16#FF#);
      Buf (3) := Byte (Shift_Right (Val, 24) and 16#FF#);
      Buf (4) := Byte (Shift_Right (Val, 32) and 16#FF#);
      Buf (5) := Byte (Shift_Right (Val, 40) and 16#FF#);
      Buf (6) := Byte (Shift_Right (Val, 48) and 16#FF#);
      Buf (7) := Byte (Shift_Right (Val, 56) and 16#FF#);
      Absorb (Sp, Buf);
   end Absorb_U64;

   procedure Finalize (Sp : in out Sponge) is
   begin
      --  SHAKE-256 padding: 0x1F, then zeros, then 0x80 at rate-1
      XOR_Byte (Sp.S, Sp.Absorbed, 16#1F#);
      XOR_Byte (Sp.S, Shake256_Rate - 1, 16#80#);
      Permute (Sp.S);
      Sp.Absorbed := 0;
      Sp.Squeezed := True;
   end Finalize;

   procedure Squeeze
     (Sp     : in out Sponge;
      Output : out Byte_Seq)
   is
      subtype Rate_Index is Natural range 0 .. Shake256_Rate;
      Pos : Rate_Index := Sp.Absorbed;
   begin
      for I in Output'Range loop
         if Pos = Shake256_Rate then
            Permute (Sp.S);
            Pos := 0;
         end if;
         pragma Assert (Pos < Shake256_Rate);
         Output (I) := Get_Byte (Sp.S, Pos);
         Pos := Pos + 1;
      end loop;
      Sp.Absorbed := Pos;
   end Squeeze;

end SPARKEntropy.Keccak;
