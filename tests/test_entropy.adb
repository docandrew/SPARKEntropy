with Ada.Text_IO;    use Ada.Text_IO;
with Interfaces;     use Interfaces;
with SPARKEntropy;   use SPARKEntropy;

procedure Test_Entropy is
   State : Entropy_State;
   OK    : Boolean;
   Buf   : Byte_Seq (0 .. 31);
begin
   Put_Line ("SPARKEntropy Test");
   Put_Line ("=================");

   Put ("Initializing (1024 samples)... ");
   Init (State, OK);
   if not OK then
      Put_Line ("FAILED — timer unsuitable");
      return;
   end if;
   Put_Line ("OK");

   for Round in 1 .. 5 loop
      Put ("Generate 32 bytes #" & Round'Image & ": ");
      Generate (State, Buf, OK);
      if not OK then
         Put_Line ("FAILED — health test");
         return;
      end if;
      for I in Buf'Range loop
         declare
            H : constant String := Unsigned_8'Image (Unsigned_8 (Buf (I)));
         begin
            if Unsigned_8 (Buf (I)) < 16 then
               Put ("0");
            end if;
            --  Simple hex output
            declare
               V : constant Unsigned_8 := Unsigned_8 (Buf (I));
               Hi : constant Natural := Natural (Shift_Right (V, 4));
               Lo : constant Natural := Natural (V and 16#0F#);
               Hex : constant String := "0123456789abcdef";
            begin
               Put (Hex (Hi + 1) & Hex (Lo + 1));
            end;
         end;
      end loop;
      New_Line;
   end loop;

   Put_Line ("PASS");
end Test_Entropy;
