--  Dump raw entropy bytes to stdout for analysis with NIST SP 800-90B tools.
--  Usage: dump_entropy | head -c 1048576 > entropy.bin
--         ea_non_iid -i -a entropy.bin 8

with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Command_Line;
with Interfaces;            use Interfaces;
with SPARKEntropy;          use SPARKEntropy;

procedure Dump_Entropy is
   package SIO renames Ada.Streams.Stream_IO;

   State : Entropy_State;
   OK    : Boolean;

   --  Default: 1 MB (1048576 bytes), enough for NIST testing
   Total : Natural := 1048576;
   Chunk_Size : constant Natural := 1024;
   Written : Natural := 0;

   F : SIO.File_Type;
begin
   --  Parse optional size argument
   if Ada.Command_Line.Argument_Count >= 1 then
      Total := Natural'Value (Ada.Command_Line.Argument (1));
   end if;

   --  Parse optional output file (default: entropy.bin)
   declare
      Filename : constant String :=
         (if Ada.Command_Line.Argument_Count >= 2
          then Ada.Command_Line.Argument (2)
          else "entropy.bin");
   begin
      SIO.Create (F, SIO.Out_File, Filename);
   end;

   Ada.Text_IO.Put_Line ("SPARKEntropy dump: " & Total'Image & " bytes");

   Init (State, OK);
   if not OK then
      Ada.Text_IO.Put_Line ("Init FAILED — timer unsuitable");
      SIO.Close (F);
      return;
   end if;
   Ada.Text_IO.Put_Line ("Init OK, generating...");

   while Written < Total loop
      declare
         Chunk : constant Natural :=
            Natural'Min (Chunk_Size, Total - Written);
         Raw : Byte_Seq (0 .. Chunk - 1);
         B   : Stream_Element_Array (1 .. Stream_Element_Offset (Chunk));
      begin
         Generate (State, Raw, OK);
         if not OK then
            Ada.Text_IO.Put_Line ("Generate FAILED at byte" & Written'Image);
            SIO.Close (F);
            return;
         end if;

         for I in Raw'Range loop
            B (Stream_Element_Offset (I) + 1) := Stream_Element (Raw (I));
         end loop;
         SIO.Write (F, B);
         Written := Written + Chunk;
      end;
   end loop;

   SIO.Close (F);
   Ada.Text_IO.Put_Line ("Done:" & Written'Image & " bytes written");
end Dump_Entropy;
