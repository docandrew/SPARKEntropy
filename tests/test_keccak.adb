--  SHAKE-256 test vectors from NIST CAVP (ShortMsg, 256-bit output)
--  Source: https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-
--  Validation-Program/documents/sha3/shakebytetestvectors.zip

with Ada.Text_IO;       use Ada.Text_IO;
with Interfaces;        use Interfaces;
with SPARKEntropy;      use SPARKEntropy;
with SPARKEntropy.Keccak;

procedure Test_Keccak is

   function Hex (B : Byte) return String is
      H : constant String := "0123456789abcdef";
      Hi : constant Natural := Natural (Shift_Right (Unsigned_8 (B), 4));
      Lo : constant Natural := Natural (Unsigned_8 (B) and 16#0F#);
   begin
      return H (Hi + 1) & H (Lo + 1);
   end Hex;

   function Hex_Str (S : Byte_Seq) return String is
      Result : String (1 .. S'Length * 2);
      Pos    : Natural := 1;
   begin
      for I in S'Range loop
         Result (Pos .. Pos + 1) := Hex (S (I));
         Pos := Pos + 2;
      end loop;
      return Result;
   end Hex_Str;

   --  Parse hex string to Byte_Seq
   function From_Hex (S : String) return Byte_Seq is
      Result : Byte_Seq (0 .. S'Length / 2 - 1);
      function Nibble (C : Character) return Byte is
      begin
         case C is
            when '0' .. '9' => return Byte (Character'Pos (C) - Character'Pos ('0'));
            when 'a' .. 'f' => return Byte (Character'Pos (C) - Character'Pos ('a') + 10);
            when 'A' .. 'F' => return Byte (Character'Pos (C) - Character'Pos ('A') + 10);
            when others      => return 0;
         end case;
      end Nibble;
   begin
      for I in Result'Range loop
         Result (I) := Nibble (S (S'First + I * 2)) * 16
                     + Nibble (S (S'First + I * 2 + 1));
      end loop;
      return Result;
   end From_Hex;

   procedure Test_SHAKE256
     (Name     : String;
      Input    : Byte_Seq;
      Expected : String;
      Pass     : in out Natural;
      Fail     : in out Natural)
   is
      Sp     : Sponge;
      Output : Byte_Seq (0 .. Expected'Length / 2 - 1);
      Got    : String (1 .. Expected'Length);
   begin
      Keccak.Reset (Sp);
      if Input'Length > 0 then
         Keccak.Absorb (Sp, Input);
      end if;
      Keccak.Finalize (Sp);
      Keccak.Squeeze (Sp, Output);
      Got := Hex_Str (Output);

      Put ("  " & Name & ": ");
      declare
         Exp_Lower : String (Expected'Range);
      begin
         for I in Expected'Range loop
            case Expected (I) is
               when 'A' .. 'F' =>
                  Exp_Lower (I) := Character'Val (
                     Character'Pos (Expected (I)) + 32);
               when others =>
                  Exp_Lower (I) := Expected (I);
            end case;
         end loop;

         if Got = Exp_Lower then
            Put_Line ("PASS");
            Pass := Pass + 1;
         else
            Put_Line ("FAIL");
            Put_Line ("    expected: " & Exp_Lower);
            Put_Line ("    got:      " & Got);
            Fail := Fail + 1;
         end if;
      end;
   end Test_SHAKE256;

   Pass_Count : Natural := 0;
   Fail_Count : Natural := 0;
   Empty      : Byte_Seq (1 .. 0);  --  empty array

begin
   Put_Line ("SHAKE-256 Test Vectors (NIST CAVP)");
   Put_Line ("==================================");
   New_Line;

   --  Test 1: Empty input
   Test_SHAKE256
     ("Empty input (0 bytes)",
      Empty,
      "46B9DD2B0BA88D13233B3FEB743EEB243FCD52EA62B81B82B50C27646ED5762F",
      Pass_Count, Fail_Count);

   --  Test 2: 1 byte (0x0F)
   Test_SHAKE256
     ("1 byte (0x0F)",
      From_Hex ("0F"),
      "AABB07488FF9EDD05D6A603B7791B60A16D45093608F1BADC0C9CC9A9154F215",
      Pass_Count, Fail_Count);

   --  Test 3: 3 bytes (0x21EDA6)
   Test_SHAKE256
     ("3 bytes (21EDA6)",
      From_Hex ("21EDA6"),
      "F7D02B4512BE5DDCC25D148C71664DFD34E16ABEA26D6E7287F45E08ED6FCD87",
      Pass_Count, Fail_Count);

   --  Test 4: 4 bytes
   Test_SHAKE256
     ("4 bytes (4A71964B)",
      From_Hex ("4A71964B"),
      "7B7E12D2A520E232FDE6C41DBBB2B8B74C2912FB3F15404F7304FE46691430C9",
      Pass_Count, Fail_Count);

   --  Test 5: 8 bytes
   Test_SHAKE256
     ("8 bytes (587CB398FE82FFDA)",
      From_Hex ("587CB398FE82FFDA"),
      "54F5DDDB85F62DBA7DC4727D502BDEE959FB665BD482BD0CE31CBDD1A042E4B5",
      Pass_Count, Fail_Count);

   --  Test 6: 20 bytes
   Test_SHAKE256
     ("20 bytes",
      From_Hex ("AAF1F64F3DF3FD4D422ACBCB5491FF3835B57E32"),
      "333D096475B6A6D45C87B5AFC7E8CB2284456B84BD3E30A9B264492539ED3159",
      Pass_Count, Fail_Count);

   --  Test 7: 200 bytes (1600 bits, full Keccak state)
   Test_SHAKE256
     ("200 bytes (1600 bits)",
      From_Hex (
         "D00DF64C4BB9E2FD16FB6F9CA746D6CF162015EC7326E41A5D51E9B3D0792FED" &
         "3F17D5BAE34F03EC522E229D53304DCEF105024ECE941EDEBA410892846B2C7A" &
         "1039AB82AA9750979A7BC70BF96D093BC3461B6F2D38F801380ECCC286B56299" &
         "6CFCE06D4A98B245176BC4AE4006F45EB36CC71636185ACDFE429C0A7D5FBB92" &
         "7BE7DC43685A0F40F185824ED102F57EEAFE6D0D943E2D883564E233126F1EAC" &
         "648207CCAFE651CE4F5169B35369F3E48F84771AEDB2577B04FD0506ECEF7230" &
         "5055CACFC4435E38"),
      "67302648E0082254D8D342B4EB8070EF9A44E0FC55C3D9A3F20613E4824AFF21",
      Pass_Count, Fail_Count);

   --================================================================
   --  Keccak-f[1600] permutation test (XKCP test vectors)
   --================================================================
   New_Line;
   Put_Line ("Keccak-f[1600] Permutation Tests");
   Put_Line ("================================");
   New_Line;

   --  Test 8: All-zero input → known output
   declare
      S : Keccak_State := (others => 0);
      Expected : constant array (0 .. 24) of U64 :=
        (16#F1258F7940E1DDE7#, 16#84D5CCF933C0478A#,
         16#D598261EA65AA9EE#, 16#BD1547306F80494D#,
         16#8B284E056253D057#, 16#FF97A42D7F8E6FD4#,
         16#90FEE5A0A44647C4#, 16#8C5BDA0CD6192E76#,
         16#AD30A6F71B19059C#, 16#30935AB7D08FFC64#,
         16#EB5AA93F2317D635#, 16#A9A6E6260D712103#,
         16#81A57C16DBCF555F#, 16#43B831CD0347C826#,
         16#01F22F1A11A5569F#, 16#05E5635A21D9AE61#,
         16#64BEFEF28CC970F2#, 16#613670957BC46611#,
         16#B87C5A554FD00ECB#, 16#8C3EE88A1CCF32C8#,
         16#940C7922AE3A2614#, 16#1841F924A2C509E4#,
         16#16F53526E70465C2#, 16#75F644E97F30A13B#,
         16#EAF1FF7B5CECA249#);
      OK : Boolean := True;
   begin
      Keccak.Permute (S);
      for I in S'Range loop
         if S (I) /= Expected (I) then
            OK := False;
         end if;
      end loop;
      Put ("  Permute(all-zero): ");
      if OK then
         Put_Line ("PASS");
         Pass_Count := Pass_Count + 1;
      else
         Put_Line ("FAIL");
         Fail_Count := Fail_Count + 1;
      end if;
   end;

   --  Test 9: Two iterations (feed output back in)
   declare
      S : Keccak_State := (others => 0);
      Expected2 : constant array (0 .. 24) of U64 :=
        (16#2D5C954DF96ECB3C#, 16#6A332CD07057B56D#,
         16#093D8D1270D76B6C#, 16#8A20D9B25569D094#,
         16#4F9C4F99E5E7F156#, 16#F957B9A2DA65FB38#,
         16#85773DAE1275AF0D#, 16#FAF4F247C3D810F7#,
         16#1F1B9EE6F79A8759#, 16#E4FECC0FEE98B425#,
         16#68CE61B6B9CE68A1#, 16#DEEA66C4BA8F974F#,
         16#33C43D836EAFB1F5#, 16#E00654042719DBD9#,
         16#7CF8A9F009831265#, 16#FD5449A6BF174743#,
         16#97DDAD33D8994B40#, 16#48EAD5FC5D0BE774#,
         16#E3B8C8EE55B7B03C#, 16#91A0226E649E42E9#,
         16#900E3129E7BADD7B#, 16#202A9EC5FAA3CCE8#,
         16#5B3402464E1C3DB6#, 16#609F4E62A44C1059#,
         16#20D06CD26A8FBF5C#);
      OK : Boolean := True;
   begin
      Keccak.Permute (S);  --  first iteration
      Keccak.Permute (S);  --  second iteration
      for I in S'Range loop
         if S (I) /= Expected2 (I) then
            OK := False;
         end if;
      end loop;
      Put ("  Permute(2 iterations): ");
      if OK then
         Put_Line ("PASS");
         Pass_Count := Pass_Count + 1;
      else
         Put_Line ("FAIL");
         Fail_Count := Fail_Count + 1;
      end if;
   end;

   --================================================================
   --  SHA-3-256 tests (different padding: 0x06 vs SHAKE's 0x1F)
   --  Verifies that the Keccak core is correct independent of padding.
   --================================================================
   New_Line;
   Put_Line ("SHA-3-256 Tests (NIST CAVP)");
   Put_Line ("===========================");
   New_Line;

   declare
      --  SHA-3-256 uses the same sponge but with padding byte 0x06
      procedure Test_SHA3_256
        (Name     : String;
         Input    : Byte_Seq;
         Expected : String;
         Pass     : in out Natural;
         Fail     : in out Natural)
      is
         Sp     : Sponge;
         Output : Byte_Seq (0 .. 31);
         Got    : String (1 .. 64);
      begin
         Keccak.Reset (Sp);
         if Input'Length > 0 then
            Keccak.Absorb (Sp, Input);
         end if;
         --  SHA-3-256 padding: XOR 0x06 (not 0x1F like SHAKE)
         --  Manually finalize with SHA-3 domain separator
         declare
            use type SPARKEntropy.Byte;
         begin
            --  XOR pad byte at current position
            Sp.S (Sp.Absorbed / 8) := Sp.S (Sp.Absorbed / 8) xor
               Shift_Left (U64 (16#06#), (Sp.Absorbed mod 8) * 8);
            --  XOR 0x80 at rate-1
            Sp.S ((Shake256_Rate - 1) / 8) :=
               Sp.S ((Shake256_Rate - 1) / 8) xor
               Shift_Left (U64 (16#80#), ((Shake256_Rate - 1) mod 8) * 8);
            Keccak.Permute (Sp.S);
            Sp.Absorbed := 0;
            Sp.Squeezed := True;
         end;
         Keccak.Squeeze (Sp, Output);
         Got := Hex_Str (Output);

         Put ("  " & Name & ": ");
         declare
            Exp_Lower : String (1 .. 64);
         begin
            for I in 1 .. 64 loop
               case Expected (Expected'First + I - 1) is
                  when 'A' .. 'F' =>
                     Exp_Lower (I) := Character'Val (
                        Character'Pos (Expected (Expected'First + I - 1)) + 32);
                  when others =>
                     Exp_Lower (I) := Expected (Expected'First + I - 1);
               end case;
            end loop;
            if Got = Exp_Lower then
               Put_Line ("PASS");
               Pass := Pass + 1;
            else
               Put_Line ("FAIL");
               Put_Line ("    expected: " & Exp_Lower);
               Put_Line ("    got:      " & Got);
               Fail := Fail + 1;
            end if;
         end;
      end Test_SHA3_256;
   begin
      Test_SHA3_256 ("Empty input",
         Empty,
         "A7FFC6F8BF1ED76651C14756A061D662F580FF4DE43B49FA82D80A4B80F8434A",
         Pass_Count, Fail_Count);

      Test_SHA3_256 ("1 byte (0xCC)",
         From_Hex ("CC"),
         "677035391CD3701293D385F037BA32796252BB7CE180B00B582DD9B20AAAD7F0",
         Pass_Count, Fail_Count);

      Test_SHA3_256 ("2 bytes (41FB)",
         From_Hex ("41FB"),
         "39F31B6E653DFCD9CAED2602FD87F61B6254F581312FB6EEEC4D7148FA2E72AA",
         Pass_Count, Fail_Count);
   end;

   --================================================================
   --  Multi-block squeeze test (> 136 bytes, crosses rate boundary)
   --================================================================
   New_Line;
   Put_Line ("Multi-block Squeeze Test");
   Put_Line ("========================");
   New_Line;

   --  SHAKE-256 empty input, first 160 bytes (crosses rate=136 boundary)
   declare
      Sp     : Sponge;
      Output : Byte_Seq (0 .. 159);
      Expected_160 : constant String :=
         "46B9DD2B0BA88D13233B3FEB743EEB243FCD52EA62B81B82B50C27646ED5762F" &
         "D75DC4DDD8C0F200CB05019D67B592F6FC821C49479AB48640292EACB3B7C4BE" &
         "141E96616FB13957692CC7EDD0B45AE3DC07223C8E92937BEF84BC0EAB862853" &
         "349EC75546F58FB7C2775C38462C5010D846C185C15111E595522A6BCD16CF86" &
         "F3D122109E3B1FDD943B6AEC468A2D621A7C06C6A957C62B54DAFC3BE87567D6";
      Got : String (1 .. 320);
   begin
      Keccak.Reset (Sp);
      Keccak.Finalize (Sp);
      Keccak.Squeeze (Sp, Output);
      Got := Hex_Str (Output);

      Put ("  160 bytes (crosses rate boundary): ");
      declare
         Exp_Lower : String (1 .. 320);
      begin
         for I in 1 .. 320 loop
            case Expected_160 (I) is
               when 'A' .. 'F' =>
                  Exp_Lower (I) := Character'Val (
                     Character'Pos (Expected_160 (I)) + 32);
               when others =>
                  Exp_Lower (I) := Expected_160 (I);
            end case;
         end loop;
         if Got = Exp_Lower then
            Put_Line ("PASS");
            Pass_Count := Pass_Count + 1;
         else
            Put_Line ("FAIL");
            Put_Line ("    expected: " & Exp_Lower (1 .. 64) & "...");
            Put_Line ("    got:      " & Got (1 .. 64) & "...");
            Fail_Count := Fail_Count + 1;
         end if;
      end;
   end;

   New_Line;
   Put_Line ("Results:" & Pass_Count'Image & " passed," &
             Fail_Count'Image & " failed");
   if Fail_Count = 0 then
      Put_Line ("ALL TESTS PASSED");
   end if;
end Test_Keccak;
